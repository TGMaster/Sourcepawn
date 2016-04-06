#include <sourcemod>
#include <colors>

#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define IsSpectator(%0) (GetClientTeam(%0) == TEAM_SPECTATOR)
#define IsSurvivor(%0) (GetClientTeam(%0) == TEAM_SURVIVOR)
#define IsInfected(%0) (GetClientTeam(%0) == TEAM_INFECTED)
#define IsPouncing(%0) (g_bIsPouncing[%0])

#define BOOMER_STAGGER_TIME 4.0 // Amount of time after a boomer has been meleed that we consider the meleer the person who
// shut down the boomer, this is just a guess value..

#define ZC_SMOKER 1 
#define ZC_BOOMER 2 
#define ZC_HUNTER 3 
#define ZC_SPITTER 4 
#define ZC_JOCKEY 5 
#define ZC_CHARGER 6 
#define ZC_WITCH 7 
#define ZC_TANK 8

static g_iAlarmCarClient;

public Plugin:myinfo = 
{
	name = "L4D2 Realtime Stats",
	author = "Griffin, Philogl, Sir",
	description = "Display Skeets/Etc to Chat to clients",
	version = "1.0",
	url = "<- URL ->"
}

new				g_iSurvivorLimit							= 4;
new		Handle:	g_hCvarSurvivorLimit						= INVALID_HANDLE;
new		bool:	g_bHasRoundEnded							= false;
new				g_iBoomerClient;		// Last player to be boomer (or current boomer)
new				g_iBoomerKiller;									// Client who shot the boomer
new				g_iBoomerShover;									// Client who shoved the boomer
new				g_iLastHealth[MAXPLAYERS + 1];
new		bool:	g_bHasBoomLanded						 	= false;
new		bool:	g_bIsPouncing[MAXPLAYERS + 1];
new		Handle:	g_hBoomerShoveTimer							= INVALID_HANDLE;
new     Handle: g_hBoomerKillTimer                          = INVALID_HANDLE;
new 	Float: BoomerKillTime                               = 0.0;
new     String:Boomer[32]               // Name of Boomer

// Player temp stats
new				g_iDamageDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];			// Victim - Attacker
new				g_iShotsDealt[MAXPLAYERS + 1][MAXPLAYERS + 1];			// Victim - Attacker, count # of shots (not pellets)

new		bool:	g_bShotCounted[MAXPLAYERS + 1][MAXPLAYERS +1];		// Victim - Attacker, used by playerhurt and weaponfired

public OnPluginStart()
{
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	HookEvent("ability_use", Event_AbilityUse);
	HookEvent("lunge_pounce", Event_LungePounce);
	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("player_shoved", Event_PlayerShoved);
	HookEvent("player_now_it", Event_PlayerBoomed);
	
	HookEvent("create_panic_event", Event_Panic);
	HookEvent("triggered_car_alarm", Event_AlarmCar);
	
	g_hCvarSurvivorLimit = FindConVar("survivor_limit");
	HookConVarChange(g_hCvarSurvivorLimit, Cvar_SurvivorLimit);
	g_iSurvivorLimit = GetConVarInt(g_hCvarSurvivorLimit);
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client == 0 || !IsClientInGame(client)) return;
	
	if (IsInfected(client))
	{
		new zombieclass = GetEntProp(client, Prop_Send, "m_zombieClass");
		if (zombieclass == ZC_TANK) return;
		
		if (zombieclass == ZC_BOOMER)
		{
			// Fresh boomer spawning (if g_iBoomerClient is set and an AI boomer spawns, it's a boomer going AI)
			if (!IsFakeClient(client) || !g_iBoomerClient)
			{
				g_bHasBoomLanded = false;
				g_iBoomerClient = client;
				g_iBoomerShover = 0;
				g_iBoomerKiller = 0;
			}
			
			if (g_hBoomerShoveTimer != INVALID_HANDLE)
			{
				KillTimer(g_hBoomerShoveTimer);
				g_hBoomerShoveTimer = INVALID_HANDLE;
			}
			BoomerKillTime = 0.0;
			g_hBoomerKillTimer = CreateTimer(0.1, Timer_KillBoomer, _, TIMER_REPEAT);
		}
		
		g_iLastHealth[client] = GetClientHealth(client);
	}
}

public Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	for (new i = 1; i <= MaxClients; i++)
	{
		// [Victim][Attacker]
		g_bShotCounted[i][client] = false;
	}
}

public OnMapStart()
{
	g_bHasRoundEnded = false;
	ClearMapStats();
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_bHasRoundEnded = false;
	if (g_hBoomerKillTimer != INVALID_HANDLE)
	{
		KillTimer(g_hBoomerKillTimer);
		g_hBoomerKillTimer = INVALID_HANDLE;
		BoomerKillTime = 0.0;
	}
	g_iAlarmCarClient = 0;
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasRoundEnded) return;
	g_bHasRoundEnded = true;
	for (new i = 1; i <= MaxClients; i++)
	{
		ClearDamage(i);
	}
}

// Pounce tracking, from skeet announce
public Event_AbilityUse(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasRoundEnded) return;
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(!IsClientInGame(client) || !IsInfected(client)) return;
	new zombieclass = GetEntProp(client, Prop_Send, "m_zombieClass");
	
	if (zombieclass == ZC_HUNTER)
	{
		g_bIsPouncing[client] = true;
		CreateTimer(0.5, Timer_GroundedCheck, client, TIMER_REPEAT);
	}
}

public Event_LungePounce(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "userid"));
	new zombieclass = GetEntProp(attacker, Prop_Send, "m_zombieClass");
	
	if (zombieclass == ZC_HUNTER) g_bIsPouncing[attacker] = false;
}

public Action:Timer_GroundedCheck(Handle:timer, any:client)
{
	if (!IsClientInGame(client) || IsGrounded(client))
	{
		g_bIsPouncing[client] = false;
		KillTimer(timer);
	}
}

public Action:Timer_KillBoomer(Handle:timer)
{
	BoomerKillTime += 0.1;
}

// Jacked from skeet announce
bool:IsGrounded(client)
{
	return (GetEntProp(client, Prop_Data, "m_fFlags") & FL_ONGROUND) > 0;
}


public Event_PlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasRoundEnded) return;
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (victim == 0 || !IsClientInGame(victim)) return;
	if (!attacker || !IsClientInGame(attacker)) return;
	
	new damage = GetEventInt(event, "dmg_health");
	
	if (IsSurvivor(attacker) && IsInfected(victim))
	{
		new zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if (zombieclass == ZC_TANK) return; // We don't care about tank damage
		
		if (!g_bShotCounted[victim][attacker])
		{
			g_iShotsDealt[victim][attacker]++;
			g_bShotCounted[victim][attacker] = true;
		}
		
		new remaining_health = GetEventInt(event, "health");
		
		// Let player_death handle remainder damage (avoid overkill damage)
		if (remaining_health <= 0) return;
		
		// remainder health will be awarded as damage on kill
		g_iLastHealth[victim] = remaining_health;
		
		g_iDamageDealt[victim][attacker] += damage;
		
		if (zombieclass == ZC_BOOMER)
		{ /* Boomer Shit Here */ }
		else if (zombieclass == ZC_HUNTER)
		{ /* Hunter Shit Here */ }
		else if (zombieclass == ZC_SMOKER)
		{ /* Smoker Shit Here */ }
		else if (zombieclass == ZC_JOCKEY)
		{ /* Jockey Shit Here */ }
		else if (zombieclass == ZC_CHARGER)
		{ /* Charger Shit Here */ }
		else if (zombieclass == ZC_SPITTER)
		{ /* Spitter Shit Here */ }
	}
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasRoundEnded) return;
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (victim == 0 || !IsClientInGame(victim)) return;
	
	if (attacker == 0) return;
	
	if (!IsClientInGame(attacker))
	{
		if (IsInfected(victim)) ClearDamage(victim);
		return;
	}
	
	if (IsSurvivor(attacker) && IsInfected(victim))
	{
		new zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if (zombieclass == ZC_TANK) return; // We don't care about tank damage
		
		new lasthealth = g_iLastHealth[victim];
		g_iDamageDealt[victim][attacker] += lasthealth;
		
		if (zombieclass == ZC_BOOMER)
		{
			// Only happens on mid map plugin load when a boomer is up
			if (!g_iBoomerClient) g_iBoomerClient = victim;

			if (!IsFakeClient(g_iBoomerClient)) GetClientName(g_iBoomerClient, Boomer, sizeof(Boomer));
			else Boomer = "AI";
			
			CreateTimer(0.2, Timer_BoomerKilledCheck, victim);
			g_iBoomerKiller = attacker;
			
			if (g_hBoomerKillTimer != INVALID_HANDLE)
			{
				KillTimer(g_hBoomerKillTimer);
				g_hBoomerKillTimer = INVALID_HANDLE;
			}
		}
		else if (zombieclass == ZC_HUNTER && IsPouncing(victim))
		{ // Skeet!
			decl assisters[g_iSurvivorLimit][2];
			new assister_count, i;
			new damage = g_iDamageDealt[victim][attacker];
			new shots = g_iShotsDealt[victim][attacker];
			new String:plural[1] = "s";
			if (shots == 1) plural[0] = 0;
			for (i = 1; i <= MaxClients; i++)
			{
				if (i == attacker) continue;
				if (g_iDamageDealt[victim][i] > 0 && IsClientInGame(i))
				{
					assisters[assister_count][0] = i;
					assisters[assister_count][1] = g_iDamageDealt[victim][i];
					assister_count++;
				}
			}
			
			// Used GetClientWeapon because Melee Damage is known to be broken
			// Use l4d2_melee_fix.smx in order to make this work properly. :)
			new String:weapon[64];
			GetClientWeapon(attacker, weapon, sizeof(weapon));
			
			if (StrEqual(weapon, "weapon_melee"))
			{
				/*CPrintToChat(victim, "{green}★  {default}You were {blue}melee skeeted {default}by {olive}%N", attacker);
				CPrintToChat(attacker, "{green}★  {default}You {blue}melee{default}-{blue}skeeted {olive}%N", victim);
				
				for (new b = 1; b <= MaxClients; b++)
				{
					//Print to Specs!
					if (IsClientInGame(b) && (victim != b) && (attacker != b))
					{
						CPrintToChat(b, "{green}★  {olive}%N {default}was {blue}melee{default}-{blue}skeeted {default}by {olive}%N", victim, attacker)
					}
				}*/
				CPrintToChatAll("{green}★ {olive}%N {default}was {blue}melee-{default}skeeted {default}by {olive}%N", victim, attacker);
			}
			// Scout Headshot
			else if (GetEventBool(event, "headshot") && StrEqual(weapon, "weapon_sniper_scout"))
			{
				/*CPrintToChat(victim, "{green}★  {default}You were {blue}Headshotted {default}by {blue}Scout-Player{default}: {olive}%N", attacker);
				CPrintToChat(attacker, "{green}★  {default}You {blue}Headshotted {olive}%N {default}with the {blue}Scout", victim);
				
				for (new b = 1; b <= MaxClients; b++)
				{
					//Print to Specs!
					if (IsClientInGame(b) && (victim != b) && (attacker != b))
					{
						CPrintToChat(b, "{green}★  {olive}%N {default}was {blue}Headshotted {default}by {blue}Scout-Player{default}: {olive}%N", victim, attacker);
					}
				}*/
				CPrintToChatAll("{green}★ {olive}%N {default}was {blue}headshotted {default}by {olive}%N", victim, attacker);
			}
			else if (assister_count)
			{
				// Sort by damage, descending
				SortCustom2D(assisters, assister_count, ClientValue2DSortDesc);
				decl String:assister_string[128];
				decl String:buf[MAX_NAME_LENGTH + 8];
				new assist_shots = g_iShotsDealt[victim][assisters[0][0]];
				// Construct assisters string
				Format(assister_string, sizeof(assister_string), "%N {default}({green}%d{default}/{green}%d {default}shot%s)",
				assisters[0][0],
				assisters[0][1],
				g_iShotsDealt[victim][assisters[0][0]],
				assist_shots == 1 ? "":"s");
				for (i = 1; i < assister_count; i++)
				{
					assist_shots = g_iShotsDealt[victim][assisters[i][0]];
					Format(buf, sizeof(buf), ", %N {default}({green}%d{default}/{green}%d {default}shot%s)",
					assisters[i][0],
					assisters[i][1],
					assist_shots,
					assist_shots == 1 ? "":"s");
					StrCat(assister_string, sizeof(assister_string), buf);
				}
				/*
				// Print to assisters
				for (i = 0; i < assister_count; i++)
				{
					CPrintToChat(assisters[i][0], "{green}★ {olive}%N {default}teamskeeted {olive}%N {default}for {blue}%d damage {default}in {blue}%d shot%s{default}. Assisted by: {olive}%s",
					attacker, victim, damage, shots, plural, assister_string);
				}
				// Print to victim
				CPrintToChat(victim, "{green}★  {default}You were teamskeeted by {olive}%N {default}for {blue}%d damage {default}in {blue}%d shot%s{default}. Assisted by: {olive}%s",
				attacker, damage, shots, plural, assister_string);
				
				// Finally print to attacker
				CPrintToChat(attacker, "{green}★  {default}You teamskeeted {olive}%N {default}for {blue}%d damage {default}in {blue}%d shot%s{default}. Assisted by: {olive}%s",
				victim, damage, shots, plural, assister_string);
				
				//Print to Specs!
				for (new b = 1; b <= MaxClients; b++)
				{
					if (IsClientInGame(b) && (IsSpectator(b)))
					{
						CPrintToChat(b, "{green}★  {olive}%N {default}teamskeeted {olive}%N {default}for {blue}%d damage {default}in {blue}%d shot%s{default}. Assisted by: {olive}%s",
						attacker, victim, damage, shots, plural, assister_string);
					}
				}*/
				CPrintToChatAll("{green}★ {olive}%N {default}teamskeeted {olive}%N {default}for {blue}%d damage {default}in {blue}%d {default}shot%s. Assisted by: {olive}%s",
				attacker, victim, damage, shots, plural, assister_string);
			}
			else
			{
				/*CPrintToChat(victim, "{green}★  {default}You were skeeted by {olive}%N {default}in {blue}%d shot%s", attacker, shots, plural);
				
				CPrintToChat(attacker, "{green}★  {default}You skeeted {olive}%N {default}in {blue}%d shot%s", victim, shots, plural);
				
				for (new b = 1; b <= MaxClients; b++)
				{
					//Print to Everyone Else!
					if (IsClientInGame(b) && (victim != b) && attacker != b)
					{
						CPrintToChat(b, "{green}★  {olive}%N {default}skeeted {olive}%N {default}in {blue}%d shot%s", attacker, victim, shots, plural);
					}
				}*/
				CPrintToChatAll("{green}★ {olive}%N {default}skeeted {olive}%N {default}in {blue}%d {default}shot%s.", attacker, victim, shots, plural);
			}
		}
	}
	if (IsInfected(victim)) ClearDamage(victim);
}

public Action:Timer_BoomerKilledCheck(Handle:timer)
{
	BoomerKillTime = BoomerKillTime - 0.2;
	
	if (g_bHasBoomLanded || BoomerKillTime > 2.0)
	{
		g_iBoomerClient = 0;
		BoomerKillTime = 0.0;
		return;
	}
	
	if (IsClientInGame(g_iBoomerKiller))
	{
		if (IsClientInGame(g_iBoomerClient))
		{
			//Boomer was Shoved before he was Killed!
			if (g_iBoomerShover != 0 && IsClientInGame(g_iBoomerShover))
			{	
				// Shover is Killer
				if (g_iBoomerShover == g_iBoomerKiller)
				{
					//CPrintToChatAll("{green}★  {olive}%N {default}shoved and popped {olive}%s{default}'s Boomer in {blue}%0.1fs", g_iBoomerKiller, Boomer, BoomerKillTime);
				}
				// Someone Shoved and Someone Killed
				else
				{
					//CPrintToChatAll("{green}★  {olive}%N {default}shoved and {olive}%N {default}popped {olive}%s{default}'s Boomer in {blue}%0.1fs", g_iBoomerShover, g_iBoomerKiller, Boomer, BoomerKillTime);
				}
			}
			//Boomer got Popped without Shove
			else
			{
				//CPrintToChatAll("{green}★  {olive}%N {default}has shutdown {olive}%s{default}'s Boomer in {blue}%0.1fs", g_iBoomerKiller, Boomer, BoomerKillTime);
			}
		}
	}
	
	g_iBoomerClient = 0;
	BoomerKillTime = 0.0;
}

public Event_PlayerShoved(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasRoundEnded) return;
	new victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (victim == 0 ||
	!IsClientInGame(victim) ||
	!IsInfected(victim)
	) return;
	
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (attacker == 0 ||				// World dmg?
	!IsClientInGame(attacker) ||	// Unsure
	!IsSurvivor(attacker)
	) return;
	
	new zombieclass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	if (zombieclass == ZC_BOOMER)
	{
		if (g_hBoomerShoveTimer != INVALID_HANDLE)
		{
			KillTimer(g_hBoomerShoveTimer);
			if (!g_iBoomerShover || !IsClientInGame(g_iBoomerShover)) g_iBoomerShover = attacker;
		}
		else
		{
			g_iBoomerShover = attacker;
		}
		g_hBoomerShoveTimer = CreateTimer(BOOMER_STAGGER_TIME, Timer_BoomerShove);
	}
}

public Action:Timer_BoomerShove(Handle:timer)
{
	// PrintToChatAll("[DEBUG] BoomerShove timer expired, credit for boomer shutdown is available to anyone at this point!");
	g_hBoomerShoveTimer = INVALID_HANDLE;
	g_iBoomerShover = 0;
}

public Event_PlayerBoomed(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bHasBoomLanded) return;
	g_bHasBoomLanded = true;
	
	// Doesn't matter if we log stats to an out of play client, won't affect anything
	// if (!IsClientInGame(g_iBoomerClient) || IsFakeClient(g_iBoomerClient)) return;
	
	// We credit the person who spawned the boomer with booms even if it went AI
	if (GetEventBool(event, "exploded"))
	{
		// Proxy Boom!
		if (g_iBoomerShover != 0)
		{
			/*if (g_iBoomerKiller == g_iBoomerShover)
			{
				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i))
					{
						if (IsSurvivor(i) || (IsSpectator(i))) CPrintToChat(i, "{green}★  {olive}%N {default}shoved {olive}%s{default}'s Boomer, but popped it too early", g_iBoomerShover, Boomer);
					}
				}
			}
			else
			{
				for (new i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i))
					{
						if (IsSurvivor(i) || (IsSpectator(i))) CPrintToChat(i, "{green}★  {olive}%N {default}shoved {olive}%s{default}'s Boomer, but {olive}%N {default}popped it too early", g_iBoomerShover, Boomer, g_iBoomerKiller);
					}
				}
			}
			*/
		}
	}
	else
	{
		// Boomer > Survivor Skills.
	}
}


// Car Alarm Stuff!
public Event_Panic(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_iAlarmCarClient = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(0.5, Clear, g_iAlarmCarClient);
}

// g_iAlarmCarClient cleared.
public Action:Clear(Handle:timer) g_iAlarmCarClient = 0;

// Found you..! Sneaky Car Shooter.
public Action:Event_AlarmCar(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_iAlarmCarClient && IsClientInGame(g_iAlarmCarClient) && GetClientTeam(g_iAlarmCarClient) == 2)
	{
		//CPrintToChatAll("{green}★  {olive}%N {default}triggered an {olive}Alarmed Car", g_iAlarmCarClient);
		g_iAlarmCarClient = 0;
	}
}

public Cvar_SurvivorLimit(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_iSurvivorLimit = StringToInt(newValue);
}

ClearMapStats()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		ClearDamage(i);
	}
	g_iAlarmCarClient = 0;
}

ClearDamage(client)
{
	g_iLastHealth[client] = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		g_iDamageDealt[client][i] = 0;
		g_iShotsDealt[client][i] = 0;
	}
}

public ClientValue2DSortDesc(x[], y[], const array[][], Handle:data)
{
	if (x[1] > y[1]) return -1;
	else if (x[1] < y[1]) return 1;
	else return 0;
}