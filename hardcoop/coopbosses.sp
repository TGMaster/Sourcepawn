#pragma semicolon 1

#define DEBUG 0
#define INFECTED_TEAM 3

#define ZC_WITCH 7
#define ZC_TANK 8
#define SPAWN_ATTEMPT_INTERVAL 0.5
#define MAX_SPAWN_ATTEMPTS 60

#define PLUGIN_AUTHOR "Breezy"
#define PLUGIN_VERSION "1.0"

#define MAX(%0,%1) (((%0) > (%1)) ? (%0) : (%1))

#include <sourcemod>
#include <sdktools>
#include <l4d2_direct>
#include <left4downtown>
#define L4D2UTIL_STOCKS_ONLY
#include <l4d2util>
#include <colors>
#include <smlib>

// Bibliography: "current" by "CanadaRox"

public Plugin:myinfo = 
{
	name = "Coop Bosses",
	author = PLUGIN_AUTHOR,
	description = "Ensures there is exactly one tank on every non finale map in coop",
	version = PLUGIN_VERSION,
	url = ""
};

new Handle:hCvarDirectorNoBosses; // blocks witches unfortunately, needs testing for reliability with tanks

#if DEBUG
new g_iMaxFlow;
#endif
// Tank
new g_iTankPercent;
new g_iMapTankSpawnAttemptCount;
new g_bIsTankTryingToSpawn;
new g_bHasEncounteredTank;
new g_bIsRoundActive;
new g_bIsFinale;
new bool:IsAnnounceToChat;

// Witch
new g_bIsWitchKilled;
new g_iWitchPercent;
new g_iMapWitchSpawnAttemptCount;
new g_bIsWitchTryingToSpawn;
new g_bHasEncounteredWitch;

public OnPluginStart() {
	// Command
	RegConsoleCmd("sm_boss", Cmd_BossPercent, "Spawn percent for boss");
	RegConsoleCmd("sm_tank", Cmd_BossPercent, "Spawn percent for boss");
	RegConsoleCmd("sm_witch", Cmd_BossPercent, "Spawn percent for boss");
	RegConsoleCmd("sm_t", Cmd_BossPercent, "Spawn percent for boss");
	
	// Event hooks
	//HookEvent("tank_spawn", LimitTankSpawns, EventHookMode_Pre);
	HookEvent("mission_lost", EventHook:OnRoundOver, EventHookMode_PostNoCopy);
	HookEvent("map_transition", EventHook:OnRoundOver, EventHookMode_PostNoCopy);
	HookEvent("finale_win", EventHook:OnRoundOver, EventHookMode_PostNoCopy);
	HookEvent("finale_start", EventHook:OnFinaleStart, EventHookMode_PostNoCopy);
	HookEvent("tank_spawn", Event_TankSpawn, EventHookMode_PostNoCopy);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_PostNoCopy);
	//HookEvent("tank_killed", Event_TankDead, EventHookMode_PostNoCopy);
	
	// Console Variables
	hCvarDirectorNoBosses = FindConVar("director_no_bosses");
}

public OnPluginEnd() {
	ResetConVar(hCvarDirectorNoBosses);
}

public Action:Cmd_BossPercent(client, args) {
	if (g_bIsRoundActive) {
		if (client > 0) {
			PrintBossPercents(client);
		} else {
			for (new i = 1; i <= MaxClients; i++)
				if (IsClientConnected(i) && IsClientInGame(i))
					PrintBossPercents(i);
		}		
	} 
}


/***********************************************************************************************************************************************************************************

																				PER ROUND
																	
***********************************************************************************************************************************************************************************/

// Announce boss percent
public Action:L4D_OnFirstSurvivorLeftSafeArea() {
	#if DEBUG
	g_iMaxFlow = 0;
	#endif
	g_bIsRoundActive = true;
	
	g_bHasEncounteredTank = false;
	g_iMapTankSpawnAttemptCount = 0;
	g_bIsTankTryingToSpawn = false;
	g_bIsFinale = false;
	
	g_bHasEncounteredWitch = false;
	g_iMapWitchSpawnAttemptCount = 0;
	g_bIsWitchTryingToSpawn = false;
	g_bIsWitchKilled = false;
	
	g_iTankPercent = GetRandomInt(20, 80); // Tank percent
	g_iWitchPercent = GetRandomInt(20, 80); // Witch percent
	if (Math_Abs(g_iWitchPercent-g_iWitchPercent) < 10) {
		g_iWitchPercent -= 12;
	}
	for (new i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i) && IsClientInGame(i))
			PrintBossPercents(i);
	// Limit tanks
	SetConVarBool(hCvarDirectorNoBosses, true); 
}

public OnRoundOver() {
	g_bIsFinale = false;
	g_bIsRoundActive = false;
	g_bHasEncounteredTank = false;
	g_bHasEncounteredWitch = false;
}

public OnMapStart() {
	IsAnnounceToChat = false;
	PrecacheSound("ui/pickup_secret01.wav");
}

/***********************************************************************************************************************************************************************************

																			TANK SPAWN MANAGEMENT
																	
***********************************************************************************************************************************************************************************/

// Track on every game frame whether the survivor percent has reached the boss percent
public OnGameFrame() {
	// If survivors have left saferoom
	if (g_bIsRoundActive) {
		// If they have surpassed the boss percent
		new iMaxSurvivorCompletion = GetMaxSurvivorCompletion();
		
		// ===================== TANK =====================
		if (iMaxSurvivorCompletion+10 >= g_iTankPercent) {
			
			// If they have not already fought the tank
			if (!g_bHasEncounteredTank && !g_bIsFinale) {			
				if (!g_bIsTankTryingToSpawn) {
#if DEBUG
	PrintToChatAll("[CB] Attempting to spawn tank at %d%% map distance...", g_iTankPercent); 
#endif
					g_bIsTankTryingToSpawn = true;
					CreateTimer( SPAWN_ATTEMPT_INTERVAL, Timer_SpawnTank, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
				} 
			}
		}
		
		// ===================== WITCH =====================
		if (iMaxSurvivorCompletion+6 >= g_iWitchPercent) {
			// If they have not already fought the witch
			if (!g_bHasEncounteredWitch && !g_bIsFinale) {			
				if (!g_bIsWitchTryingToSpawn) {
#if DEBUG
	PrintToChatAll("[CB] Attempting to spawn witch at %d%% map distance...", g_iWitchPercent); 
#endif
					g_bIsWitchTryingToSpawn = true;
					CreateTimer( SPAWN_ATTEMPT_INTERVAL, Timer_SpawnWitch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );
				} 
			}
		}
	}  
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2]) {
	//Proceed if this player is a tank
	if(IsBotTank(client)) {
		if (!IsAnnounceToChat) {
			CPrintToChatAll("{olive}Tank {default}has spawned! Be careful!");
			EmitSoundToAll("ui/pickup_secret01.wav");
			IsAnnounceToChat = true;
		}
	}
}

public Action:Timer_SpawnTank( Handle:timer ) {
	#if DEBUG	
	PrintToChatAll("Spawn attempts: %d", g_iMapTankSpawnAttemptCount);
	#endif
	// spawn a tank with z_spawn_old (cmd uses director to find a suitable location)			
	if( IsTankInPlay() || g_iMapTankSpawnAttemptCount >= MAX_SPAWN_ATTEMPTS ) {
		g_bHasEncounteredTank = true;
		//PrintToChatAll("[CB] Percentage Tank spawned or max spawn attempts reached..."); 
		return Plugin_Stop; 
	} else {
		CheatCommand("z_spawn_old", "tank", "auto");
		++g_iMapTankSpawnAttemptCount;
		return Plugin_Continue;
	}
}

public Action:Timer_SpawnWitch( Handle:timer ) {
	#if DEBUG	
	PrintToChatAll("Spawn attempts: %d", g_iMapWitchSpawnAttemptCount);
	#endif
	// spawn a witch with z_spawn_old (cmd uses director to find a suitable location)			
	if( g_bIsWitchKilled || g_iMapWitchSpawnAttemptCount >= 1 ) {
		g_bHasEncounteredWitch = true;
		//PrintToChatAll("[CB] Percentage Tank spawned or max spawn attempts reached..."); 
		return Plugin_Stop; 
	} else {
		CheatCommand("z_spawn_old", "witch", "auto");
		++g_iMapWitchSpawnAttemptCount;
		return Plugin_Continue;
	}
}

// Slay extra tanks
public Action:LimitTankSpawns(Handle:event, String:name[], bool:dontBroadcast) {
	// Do not touch finale tanks
	if (g_bIsFinale) return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new tank = client;
	if (IsBotTank(tank)) {
		// If this tank is too early or late, kill it
		if (GetMaxSurvivorCompletion() < g_iTankPercent || g_bHasEncounteredTank)  {
			ForcePlayerSuicide(tank);		
#if DEBUG
	decl String:mapName[32];
	GetCurrentMap(mapName, sizeof(mapName));
	LogError("Map %s:", mapName);
	if (GetMaxSurvivorCompletion() < g_iTankPercent) {
		LogError("Premature tank spawned. Slaying...");
	} else if (g_bHasEncounteredTank) {
		LogError("Surplus tank spawned. Slaying...");
	}
	LogError("- Tank Percent: %i", g_iTankPercent);
	LogError("- MaxSurvivorCompletion: %i", GetMaxSurvivorCompletion()); 
#endif			
		} 		
	}
	
	return Plugin_Continue;
}

public Event_TankSpawn(Handle:event, const String:name[], bool:dontBroadcast) {
    new tank = GetClientOfUserId(GetEventInt(event, "userid"));
    CreateTimer( 3.0, Timer_AggravateTank, any:tank, TIMER_FLAG_NO_MAPCHANGE );
    // Aggravate the tank upon spawn in case he spawns out of survivor's line of sight
}

public Event_TankDead(Handle:event, const String:name[], bool:dontBroadcast) {
	if (IsAnnounceToChat)
		IsAnnounceToChat = false;
}

public Event_WitchKilled(Handle:event, const String:name[], bool:dontBroadcast) {
	g_bIsWitchKilled = true;
}

public Action:Timer_AggravateTank( Handle:timer, any:tank ) {
    // How to aggravate a tank that has spawned out of sight? Remote damage does not appear to aggravate them.
    return Plugin_Stop;
}

public OnFinaleStart() {
	g_bIsFinale = true;
	SetConVarBool(hCvarDirectorNoBosses, false); 
}

/***********************************************************************************************************************************************************************************

																				UTILITY
																	
***********************************************************************************************************************************************************************************/
// Get current survivor percent
stock GetMaxSurvivorCompletion() {
	new Float:flow = 0.0;
	decl Float:tmp_flow;
	decl Float:origin[3];
	decl Address:pNavArea;
	for (new client = 1; client <= MaxClients; client++) {
		if(IsClientInGame(client) &&
			L4D2_Team:GetClientTeam(client) == L4D2Team_Survivor)
		{
			GetClientAbsOrigin(client, origin);
			pNavArea = L4D2Direct_GetTerrorNavArea(origin);
			if (pNavArea != Address_Null)
			{
				tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
				flow = MAX(flow, tmp_flow);
			}
		}
	}
	#if DEBUG
		new current = RoundToNearest(flow * 100 / L4D2Direct_GetMapMaxFlowDistance());
		if (g_iMaxFlow < current) {
			g_iMaxFlow  = current;
			PrintToChatAll("%d%%", g_iMaxFlow );
		} 	
	#endif
	return RoundToNearest(flow * 100 / L4D2Direct_GetMapMaxFlowDistance());
}

// Executes through a dummy client, without setting sv_cheats to 1, a console command marked as a cheat
CheatCommand(String:command[], String:argument1[] = "", String:argument2[] = "") {
	new anyclient = GetAnyClient();
	if (anyclient == 0)
	{		
		anyclient = CreateFakeClient("Bot");
		ChangeClientTeam(anyclient, 1);
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

bool:IsBotTank(client) {
	// Check the input is valid
	if (!IsValidClient(client)) return false;
	// Check if player is on the infected team, a hunter, and a bot
	if (GetClientTeam(client) == INFECTED_TEAM) {
		new zombieClass = GetEntProp(client, Prop_Send, "m_zombieClass");
		if (zombieClass == ZC_TANK) {
			if(IsFakeClient(client)) { // is a bot
				return true;
			}
		}
	}
	return false; // otherwise
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

stock PrintBossPercents(client)
{
	CPrintToChat(client, "Tank: [{blue}%d%%{default}]", g_iTankPercent);
	CPrintToChat(client, "Witch: [{blue}%d%%{default}]", g_iWitchPercent);
}
