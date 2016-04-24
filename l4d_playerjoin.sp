#pragma semicolon	1

#include <sourcemod>
#include <geoip>
#undef REQUIRE_EXTENSIONS
#include <geoipcity>
#undef REQUIRE_PLUGIN
#include <colors>

#define DEBUG 0
#define	PLUGIN_VERSION		"1.0.3"

//Handle
new Handle:g_hGameMode = INVALID_HANDLE;

new hCount;
new hSlots;
new bool:g_UseGeoIPCity = false;

public Plugin:myinfo = 
{
	name			=	"Player Join Counting",
	author			=	"TGMaster, Arg!",
	description		=	"Informs other players when a client connects to the server and changes teams.",
	version			=	PLUGIN_VERSION,
	url				=	""
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("l4d_playerjoin.phrases");
	//Check Game Mode
	g_hGameMode = FindConVar("mp_gamemode");
	
	//Hook Event
	HookEvent("player_disconnect", playerDisconnect, EventHookMode_Pre);
	
	// Check if we have GeoIPCity.ext loaded
	g_UseGeoIPCity = LibraryExists("GeoIPCity");
	
	//Get Country
	RegAdminCmd("sm_geolist", Command_WhereIs, ADMFLAG_GENERIC, "sm_geolist <name or #userid> - prints geopraphical information about target(s)");
}
	
public OnLibraryAdded(const String:name[])
{
	// Is the GeoIPCity extension running?
	if(StrEqual(name, "GeoIPCity"))
		g_UseGeoIPCity = true;
}

public OnLibraryRemoved(const String:name[])
{
	// Was the GeoIPCity extension removed?
	if(StrEqual(name, "GeoIPCity"))
		g_UseGeoIPCity = false;
}

public OnMapStart()
{
	//Refresh slot count
	hCount = CheckPlayerCount();
	
	//Check game mode
	decl String:sGameMode[16];
	GetConVarString(g_hGameMode, sGameMode, sizeof(sGameMode));
	
	//Versus or Scavenge has 8 slots
	if (StrEqual(sGameMode, "versus", false) || StrEqual(sGameMode, "scavenge", false))
	{
		hSlots = 8;
	}
	
	//Campaign or Realism has slots based on l4d_superversus
	else if (StrEqual(sGameMode, "coop", false) || StrEqual(sGameMode, "realism", false))
	{
		hSlots = GetConVarInt(FindConVar("sv_maxplayers"));
	}

#if DEBUG
	RegConsoleCmd("sm_doshit", CountPlayer_Cmd);
#endif
}

/*============================= P L A Y E R    C O N N E C T ============================*/

public OnClientConnected(client)
{
	if (IsValidPlayer(client) && !IsFakeClient(client))
	{
		hCount ++;
		if (hCount <= hSlots)
			CPrintToChatAll("{olive}%N {default}is {blue}connecting{default} ({green}%i{default}/{green}%d{default})", client, hCount, hSlots);
		else
			CPrintToChatAll("{olive}%N {default}is {blue}connecting{default} to the server.", client);
	}
}

/*=========================== P L A Y E R    D I S C O N N E C T ==========================*/

public Action:playerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl String:reason[256];
	decl String:timedOut[256];
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (client && !IsFakeClient(client) && !dontBroadcast)
	{
		hCount--;
		GetEventString(event, "reason", reason, sizeof(reason));
		Format(timedOut, sizeof(timedOut), "%s timed out", client);
		
		if (strcmp(reason, timedOut) == 0 || strcmp(reason, "No Steam logon") == 0)
		{
			Format(reason, sizeof(reason), "Game crashed.");
		}
		
		CPrintToChatAll("{olive}%N {default}has {red}left {default}<{olive}%s{default}>", client, reason);
	}
	return event_PlayerDisconnect_Suppress( event, name, dontBroadcast );
}

/*===========================================================================================*/
static bool:IsValidPlayer(client) 
{
	if (0 < client <= MaxClients)
		return true;
	return false;
}

stock CheckPlayerCount()
{
	new real = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && !IsFakeClient(i)) 
			real++;
	}
	
	return real;
	
}

public Action:event_PlayerDisconnect_Suppress(Handle:event, const String:name[], bool:dontBroadcast)
{
    if (!dontBroadcast)
    {
        decl String:clientName[33], String:networkID[22], String:reason[65];
        GetEventString(event, "name", clientName, sizeof(clientName));
        GetEventString(event, "networkid", networkID, sizeof(networkID));
        GetEventString(event, "reason", reason, sizeof(reason));

        new Handle:newEvent = CreateEvent("player_disconnect", true);
        SetEventInt(newEvent, "userid", GetEventInt(event, "userid"));
        SetEventString(newEvent, "reason", reason);
        SetEventString(newEvent, "name", clientName);        
        SetEventString(newEvent, "networkid", networkID);

        FireEvent(newEvent, true);

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action:Command_WhereIs(client, args)
{
	decl String:target[65];
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS];
	decl target_count;
	decl bool:tn_is_ml;
	decl String:name[32];
	
	decl String:ip[16];
	decl String:city[46];
	decl String:region[46];
	decl String:country[46];
	decl String:ccode[3];
	decl String:ccode3[4];
	new bool:bIsLanIp;

	//not enough arguments, display usage
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_geolist <name, #userid or @targets>");
		return Plugin_Handled;
	}	

	//get command arguments
	GetCmdArg(1, target, sizeof(target));


	//get the target of this command, return error if invalid
	if ((target_count = ProcessTargetString(
			target,
			client,
			target_list,
			MAXPLAYERS,
			0,
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
				
	for (new i = 0; i < target_count; i++)
	{
		GetClientIP(target_list[i], ip, sizeof(ip)); 
		GetClientName(target_list[i], name, 32);	
		
		//detect LAN ip
		bIsLanIp = IsLanIP( ip );
		
		// Using GeoIPCity extension...
		if ( g_UseGeoIPCity )
		{
			if( !GeoipGetRecord( ip, city, region, country, ccode, ccode3 ) )
			{
				if( bIsLanIp )
				{
					Format( city, sizeof(city), "%T", "LAN City Desc", LANG_SERVER );
					Format( region, sizeof(region), "%T", "LAN Region Desc", LANG_SERVER );
					Format( country, sizeof(country), "%T", "LAN Country Desc", LANG_SERVER );
					Format( ccode, sizeof(ccode), "%T", "LAN Country Short", LANG_SERVER );
					Format( ccode3, sizeof(ccode3), "%T", "LAN Country Short 3", LANG_SERVER );
				}
				else
				{
					Format( city, sizeof(city), "%T", "Unknown City Desc", LANG_SERVER );
					Format( region, sizeof(region), "%T", "Unknown Region Desc", LANG_SERVER );
					Format( country, sizeof(country), "%T", "Unknown Country Desc", LANG_SERVER );
					Format( ccode, sizeof(ccode), "%T", "Unknown Country Short", LANG_SERVER );
					Format( ccode3, sizeof(ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
				}
			}
		}
		else // Using GeoIP default extension...
		{
			if( !GeoipCode2(ip, ccode) )
			{
				if( bIsLanIp )
				{
					Format( ccode, sizeof(ccode), "%T", "LAN Country Short", LANG_SERVER );
				}
				else
				{
					Format( ccode, sizeof(ccode), "%T", "Unknown Country Short", LANG_SERVER );
				}
			}
			
			if( !GeoipCountry(ip, country, sizeof(country)) )
			{
				if( bIsLanIp )
				{
					Format( country, sizeof(country), "%T", "LAN Country Desc", LANG_SERVER );
				}
				else
				{
					Format( country, sizeof(country), "%T", "Unknown Country Desc", LANG_SERVER );
				}
			}
			
			// Since the GeoIPCity extension isn't loaded, we don't know the city or region.
			if( bIsLanIp )
			{
				Format( city, sizeof(city), "%T", "LAN City Desc", LANG_SERVER );
				Format( region, sizeof(region), "%T", "LAN Region Desc", LANG_SERVER );
				Format( ccode3, sizeof(ccode3), "%T", "LAN Country Short 3", LANG_SERVER );
			}
			else
			{
				Format( city, sizeof(city), "%T", "Unknown City Desc", LANG_SERVER );
				Format( region, sizeof(region), "%T", "Unknown Region Desc", LANG_SERVER );
				Format( ccode3, sizeof(ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
			}
		}
		
		// Fallback for unknown/empty location strings
		if( StrEqual( city, "" ) )
		{
			Format( city, sizeof(city), "%T", "Unknown City Desc", LANG_SERVER );
		}
		
		if( StrEqual( region, "" ) )
		{
			Format( region, sizeof(region), "%T", "Unknown Region Desc", LANG_SERVER );
		}
		
		if( StrEqual( country, "" ) )
		{
			Format( country, sizeof(country), "%T", "Unknown Country Desc", LANG_SERVER );
		}
		
		if( StrEqual( ccode, "" ) )
		{
			Format( ccode, sizeof(ccode), "%T", "Unknown Country Short", LANG_SERVER );
		}
		
		if( StrEqual( ccode3, "" ) )
		{
			Format( ccode3, sizeof(ccode3), "%T", "Unknown Country Short 3", LANG_SERVER );
		}
		
		// Add "The" in front of certain countries
		if( StrContains( country, "United", false ) != -1 || 
			StrContains( country, "Republic", false ) != -1 || 
			StrContains( country, "Federation", false ) != -1 || 
			StrContains( country, "Island", false ) != -1 || 
			StrContains( country, "Netherlands", false ) != -1 || 
			StrContains( country, "Isle", false ) != -1 || 
			StrContains( country, "Bahamas", false ) != -1 || 
			StrContains( country, "Maldives", false ) != -1 || 
			StrContains( country, "Philippines", false ) != -1 || 
			StrContains( country, "Vatican", false ) != -1 )
		{
			Format( country, sizeof(country), "The %s", country );
		}
		
		ReplyToCommand( client, "%s from %s in %s/%s", name, city, region, country );
	}			
	
	return Plugin_Handled;
}

//Thanks to Darkthrone (https://forums.alliedmods.net/member.php?u=54636)
bool:IsLanIP( String:src[16] )
{
	decl String:ip4[4][4];
	new ipnum;

	if(ExplodeString(src, ".", ip4, 4, 4) == 4)
	{
		ipnum = StringToInt(ip4[0])*65536 + StringToInt(ip4[1])*256 + StringToInt(ip4[2]);
		
		if((ipnum >= 655360 && ipnum < 655360+65535) || (ipnum >= 11276288 && ipnum < 11276288+4095) || (ipnum >= 12625920 && ipnum < 12625920+255))
		{
			return true;
		}
	}

	return false;
}
