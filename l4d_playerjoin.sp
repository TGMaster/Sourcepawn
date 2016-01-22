#pragma semicolon	1

#include <sourcemod>
#include <colors>

#define DEBUG 1
#define	PLUGIN_VERSION		"1.0.2"

//Handle
new Handle:g_hGameMode = INVALID_HANDLE;

new hCount;
new hSlots;

public Plugin:myinfo = 
{
	name			=	"Player Join Counting",
	author			=	"Blazers Team",
	description		=	"Informs other players when a client connects to the server and changes teams.",
	version			=	PLUGIN_VERSION,
	url				=	""
}

public OnPluginStart()
{
	//Check Game Mode
	g_hGameMode = FindConVar("mp_gamemode");
	
	//Hook Event
	HookEvent("round_start", Event_Check);
	HookEvent("player_left_start_area", Event_Check);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}
	
public OnMapStart()
{
	//Refresh slot count
	hCount = 0;
	
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
		hSlots = GetConVarInt(FindConVar("l4d_survivor_limit"));
	}

#if DEBUG
	RegConsoleCmd("sm_doshit", CountPlayer_Cmd);
#endif
}

public OnClientConnected(client) {
	if (IsValidPlayer(client)) {
		if (!IsFakeClient(client)) 
		{
			if (0 <= hCount < hSlots) {
				hCount++;
				CPrintToChatAll("{lightgreen}%N{default} is connecting to the server ({green}%i{default}/{green}%d{default})", client, hCount, hSlots);
			}
			else if(hCount >= hSlots)
				CPrintToChatAll("{lightgreen}%N{default} is connecting to the server.", client);
		}
	}
}

/*=========================== P L A Y E R    D I S C O N N E C T ==========================*/

public OnClientDisconnect(client)
{
	if (IsValidPlayer(client)) {
		if (IsClientInGame(client)) {
			if (!IsFakeClient(client) && GetClientTeam(client) != 1) 
			{
				if(0 < hCount)
					hCount--;
				else hCount = 0;
				CreateTimer(1.0, CheckPlayerCount); //Check Slot Again
				GetEventString(event, "reason", reason, sizeof(reason))
#if DEBUG
				PrintToConsole(client, "Player Count: %i", hCount);
#endif

			}
		}
	}

}

public Action:event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	decl String:reason[128];
	decl String:fixreason[128];
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if( client && !IsFakeClient(client) && !dontBroadcast )
	{
		GetEventString(event, "reason", reason, sizeof(reason));
		
		if(StrEqual(reason, "Disconnect by user."))
			Format(fixreason,sizeof(fixreason),"Disconnect by user");
			
		if(StrEqual(reason, "No Steam logon"))
			Format(fixreason,sizeof(fixreason),"Crash game");
			
		else Format(fixreason,sizeof(fixreason),reason);
		CPrintToChatAll("{lightgreen}%N {default}has left - {green}%s{default}.", client, fixreason);
	}
}

/*===========================================================================================*/

public Action:Event_Check(Handle:event, String:event_name[], bool:dontBroadcast) {
	CreateTimer(5.0, CheckPlayerCount); //Check Slot Event
}

static bool:IsValidPlayer(client) 
{
	if (0 < client <= MaxClients)
		return true;
	return false;
}

public Action:CheckPlayerCount(Handle:timer)
{
	new real = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i)) {
			if(!IsFakeClient(i) && GetClientTeam(i) != 1)
				real++;
		}
	}
	
	hCount = real;
	
}

#if DEBUG
public Action:CountPlayer_Cmd(client, args)
{
	CreateTimer(0.5, CheckPlayerCount);
	PrintToChat(client, "Player Count: %i / %d", hCount, hSlots);
}
#endif

