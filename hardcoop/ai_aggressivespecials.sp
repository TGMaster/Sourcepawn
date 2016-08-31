#pragma semicolon 1

#define DEBUG
#define KICKDELAY 0.1
#define INFECTED_TEAM 3
#define ASSAULT_DELAY 0.3 // using 0.3 to be safe (command does not register in the first 0.2 seconds after spawn)

#define PLUGIN_AUTHOR "Breezy"
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util>
#include <left4downtown>

public Plugin:myinfo = 
{
	name = "AI: Aggressive Specials",
	author = PLUGIN_AUTHOR,
	description = "Force SI to be aggressive",
	version = PLUGIN_VERSION,
	url = ""
};


new Handle:hCvarBoomerExposedTimeTolerance;
new Handle:hCvarBoomerVomitDelay;

public OnPluginStart() {
	hCvarBoomerExposedTimeTolerance = FindConVar("boomer_exposed_time_tolerance");	
	hCvarBoomerVomitDelay = FindConVar("boomer_vomit_delay");	
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Pre);
	HookEvent("ability_use", OnAbilityUse, EventHookMode_Pre);
}

public Action:L4D_OnFirstSurvivorLeftSafeArea(client) {
    SetConVarFloat(hCvarBoomerExposedTimeTolerance, 10000.0);
    SetConVarFloat(hCvarBoomerVomitDelay, 0.1);
}

public OnPluginEnd() {
	ResetConVar(hCvarBoomerExposedTimeTolerance);
	ResetConVar(hCvarBoomerVomitDelay);
}

/***********************************************************************************************************************************************************************************

																			AGGRESSIVE UPON SPAWN

***********************************************************************************************************************************************************************************/

// Command SI to be aggressive so they do not run away
public Action:OnPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsBotInfected(client)) {
		CreateTimer(ASSAULT_DELAY, Timer_PostSpawnAssault, _, TIMER_FLAG_NO_MAPCHANGE);
	}	
}

public Action:Timer_PostSpawnAssault(Handle:timer) {
	CheatCommand("nb_assault");
	return Plugin_Stop;
}

/***********************************************************************************************************************************************************************************

																			STOP SMOKERS & SPITTERS FLEEING

***********************************************************************************************************************************************************************************/

// Stop smokers and spitters running away
public Action:OnAbilityUse(Handle:event, const String:name[], bool:dontBroadcast) {
	new String:abilityName[MAX_NAME_LENGTH];
	GetEventString(event, "ability", abilityName, sizeof(abilityName));
	if (StrEqual(abilityName, "ability_tongue") || StrEqual(abilityName, "ability_spit")) {
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		SetEntityMoveType(client, MOVETYPE_NONE);
	}
}

/***********************************************************************************************************************************************************************************

																				UTILITY

***********************************************************************************************************************************************************************************/

// Executes through a dummy client, without setting sv_cheats to 1, a console command marked as a cheat
CheatCommand(String:command[], String:argument1[] = "", String:argument2[] = "") {
	new anyclient = GetAnyClient()
	if (anyclient == 0)
	{		
		anyclient = CreateFakeClient("Bot");
		if (anyclient == 0)
		{		
			return;	
		}	
	}

	new flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
			
    FakeClientCommand(anyclient, "%s %s %s", command, argument1, argument2);

	SetCommandFlags(command, flags);
}

bool:IsBotInfected(client) {
	return (IsValidClient(client) && GetClientTeam(client) == INFECTED_TEAM && IsFakeClient(client) && IsPlayerAlive(client));
}

bool:IsValidClient(client) {
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) ) return false;      
    return true; 
}

public GetAnyClient()
{
	new i;
	for (i=1;i<=GetMaxClients();i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && (!IsFakeClient(i)))
		{
			return i;
		}
	}
	return 0;
}