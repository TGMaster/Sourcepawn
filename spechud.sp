/*
	SourcePawn is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2015 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2015 ITB CompuPhase.
	Source is Copyright (C) Valve Corporation.
	All trademarks are property of their respective owners.

	This program is free software: you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the
	Free Software Foundation, either version 3 of the License, or (at your
	option) any later version.

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
	General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <l4d2_direct>
#include <l4d2_weapon_stocks>
#include <readyup>
#include <pause>
#include <colors>
#undef REQUIRE_PLUGIN
#include <l4d2_scoremod>
#include <scoremod2>
#include <l4d_tank_control>
#define REQUIRE_PLUGIN

#define SPECHUD_DRAW_INTERVAL   0.5

#define ZOMBIECLASS_NAME(%0) (L4D2SI_Names[(%0)])

#define L4D2_ScoreMod 1
#define ScoreMod2 2

enum L4D2Gamemode
{
	L4D2Gamemode_None,
	L4D2Gamemode_Versus,
	L4D2Gamemode_Scavenge
};

enum L4D2SI
{
	ZC_None,
	ZC_Smoker,
	ZC_Boomer,
	ZC_Hunter,
	ZC_Spitter,
	ZC_Jockey,
	ZC_Charger,
	ZC_Witch,
	ZC_Tank
};

static const String:L4D2SI_Names[][] =
{
	"None",
	"Smoker",
	"Boomer",
	"Hunter",
	"Spitter",
	"Jockey",
	"Charger",
	"Witch",
	"Tank"
};

new Handle:survivor_limit;
new Handle:z_max_player_zombies;

new bool:bSpecHudActive[MAXPLAYERS + 1];
new bool:bSpecHudHintShown[MAXPLAYERS + 1];
new bool:bTankHudActive[MAXPLAYERS + 1];
new bool:bTankHudHintShown[MAXPLAYERS + 1];

new scoremode; // Tracks which scoremod plugin is loaded.
new bool:isTankControlLoaded;

public Plugin:myinfo =
{
	name = "Hyper-V HUD Manager [Public Version]",
	author = "Visor, darkid",
	description = "Provides different HUDs for spectators",
	version = "2.11",
	url = "https://github.com/Attano/smplugins"
};

public OnPluginStart()
{
	survivor_limit = FindConVar("survivor_limit");
	z_max_player_zombies = FindConVar("z_max_player_zombies");

	RegConsoleCmd("sm_spechud", ToggleSpecHudCmd);
	RegConsoleCmd("sm_tankhud", ToggleTankHudCmd);

	CreateTimer(SPECHUD_DRAW_INTERVAL, HudDrawTimer, _, TIMER_REPEAT);
	OnAllPluginsLoaded();
}

public OnAllPluginsLoaded()
{
	if (LibraryExists("l4d2_scoremod")) {
		scoremode |= L4D2_ScoreMod;
	}
	if (LibraryExists("scoremod2")) {
		scoremode |= ScoreMod2;
	}
	isTankControlLoaded = LibraryExists("l4d_tank_control");
}
public OnLibraryRemoved(const String:name[])
{
	if (strcmp(name, "l4d2_scoremod") == 0) {
		scoremode &= ~L4D2_ScoreMod;
	} else if (strcmp(name, "scoremod2") == 0) {
		scoremode &= ~ScoreMod2;
	}
	if (strcmp(name, "l4d_tank_control") == 0) {
		isTankControlLoaded = false;
	}
}
public OnLibraryAdded(const String:name[])
{
	if (strcmp(name, "l4d2_scoremod") == 0) {
		scoremode |= L4D2_ScoreMod;
	} else if (strcmp(name, "scoremod2") == 0) {
		scoremode |= ScoreMod2;
	}
	if (strcmp(name, "l4d_tank_control") == 0) {
		isTankControlLoaded = true;
	}
}

public OnClientAuthorized(client, const String:auth[])
{
	bSpecHudActive[client] = true;
	bSpecHudHintShown[client] = false;
	bTankHudActive[client] = true;
	bTankHudHintShown[client] = false;
}

public Action:ToggleSpecHudCmd(client, args)
{
	bSpecHudActive[client] = !bSpecHudActive[client];
	CPrintToChat(client, "{olive}[{default}HUD{olive}]{default} Spectator HUD is now %s.", (bSpecHudActive[client] ? "{blue}on{default}" : "{red}off{default}"));
}

public Action:ToggleTankHudCmd(client, args)
{
	bTankHudActive[client] = !bTankHudActive[client];
	CPrintToChat(client, "{olive}[{default}HUD{olive}]{default} Tank HUD is now %s.", (bTankHudActive[client] ? "{blue}on{default}" : "{red}off{default}"));
}

public Action:HudDrawTimer(Handle:hTimer)
{
	if (IsInReady() || IsInPause())
		return Plugin_Handled;

	new bool:bSpecsOnServer = false;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsSpectator(i))
		{
			bSpecsOnServer = true;
			break;
		}
	}

	if (bSpecsOnServer) // Only bother if someone's watching us
	{
		new Handle:specHud = CreatePanel();

		FillHeaderInfo(specHud);
		FillSurvivorInfo(specHud);
		FillInfectedInfo(specHud);
		FillTankInfo(specHud);
		//FillGameInfo(specHud);

		for (new i = 1; i <= MaxClients; i++)
		{
			if (!bSpecHudActive[i] || !IsSpectator(i) || IsFakeClient(i))
				continue;

			SendPanelToClient(specHud, i, DummySpecHudHandler, 3);
			if (!bSpecHudHintShown[i])
			{
				bSpecHudHintShown[i] = true;
				CPrintToChat(i, "{olive}[{default}HUD{olive}]{default} Type {green}!spechud{default} into chat to toggle the {blue}Spectator HUD{default}.");
			}
		}

		CloseHandle(specHud);
	}

	new Handle:tankHud = CreatePanel();
	if (!FillTankInfo(tankHud, true)) // No tank -- no HUD
		return Plugin_Handled;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!bTankHudActive[i] || !IsClientInGame(i) || IsFakeClient(i) || IsSurvivor(i) || (bSpecHudActive[i] && IsSpectator(i)))
			continue;

		SendPanelToClient(tankHud, i, DummyTankHudHandler, 3);
		if (!bTankHudHintShown[i])
		{
			bTankHudHintShown[i] = true;
			CPrintToChat(i, "{olive}[{default}HUD{olive}]{default} Type {green}!tankhud{default} into chat to toggle the {red}Tank HUD{default}.");
		}
	}

	CloseHandle(tankHud);
	return Plugin_Continue;
}

public DummySpecHudHandler(Handle:hMenu, MenuAction:action, param1, param2) {}
public DummyTankHudHandler(Handle:hMenu, MenuAction:action, param1, param2) {}

FillHeaderInfo(Handle:hSpecHud)
{
	decl String:server[512];
	GetConVarString(FindConVar("hostname"), server, sizeof(server));
	Format(server, sizeof(server), "%s :: Round %s", server, (InSecondHalfOfRound() ? "2" : "1"));
	DrawPanelText(hSpecHud, server);
	DrawPanelText(hSpecHud, "➜ Cmds: !spechud, !hear");
	DrawPanelText(hSpecHud, "====================================");

	decl String:buffer[512];
	Format(buffer, sizeof(buffer), "Spectator HUD | Slots %i/%i | Tickrate %i", GetRealClientCount(), GetConVarInt(FindConVar("sv_maxplayers")), RoundToNearest(1.0 / GetTickInterval()));
	DrawPanelText(hSpecHud, buffer);
}

GetMeleePrefix(client, String:prefix[], length)
{
	new secondary = GetPlayerWeaponSlot(client, _:L4D2WeaponSlot_Secondary);
	new WeaponId:secondaryWep = IdentifyWeapon(secondary);

	decl String:buf[64];
	switch (secondaryWep)
	{
		case WEPID_NONE: buf = "None";
		case WEPID_PISTOL: buf = (GetEntProp(secondary, Prop_Send, "m_isDualWielding") ? "Dual Pistols" : "Pistol");
		case WEPID_MELEE: buf = "Melee";
		case WEPID_PISTOL_MAGNUM: buf = "Deagle";
		default: buf = "?";
	}

	strcopy(prefix, length, buf);
}

FillSurvivorInfo(Handle:hSpecHud)
{
	decl String:info[512];
	decl String:buffer[64];
	decl String:name[MAX_NAME_LENGTH];
	decl String:type[3];
	new bonus;
	if (scoremode & L4D2_ScoreMod == L4D2_ScoreMod) {
		type = "H";
		bonus = HealthBonus();
	} else if (scoremode & ScoreMod2 == ScoreMod2) {
		type = "D";
		bonus = DamageBonus();
	} else {
		return;
	}

	new String:hb[128];
	Format(hb, sizeof(hb), "->1. Survivors [%sB: %d] | Current: %i%%", type, bonus, RoundToNearest(GetHighestSurvivorFlow() * 100.0));
	DrawPanelText(hSpecHud, " ");
	DrawPanelText(hSpecHud, hb);

	new survivorCount;
	for (new client = 1; client <= MaxClients && survivorCount < GetConVarInt(survivor_limit); client++)
	{
		if (!IsSurvivor(client))
			continue;

		GetClientFixedName(client, name, sizeof(name));
		if (!IsPlayerAlive(client))
		{
			Format(info, sizeof(info), "%s: Dead", name);
		}
		else
		{
			new WeaponId:primaryWep = IdentifyWeapon(GetPlayerWeaponSlot(client, _:L4D2WeaponSlot_Primary));
			GetLongWeaponName(primaryWep, info, sizeof(info));
			GetMeleePrefix(client, buffer, sizeof(buffer));
			Format(info, sizeof(info), "%s/%s", info, buffer);

			if (IsSurvivorHanging(client))
			{
				Format(info, sizeof(info), "%s: %iHP <Hanging> [%s]", name, GetSurvivorHealth(client), info);
			}
			else if (IsIncapacitated(client))
			{
				Format(info, sizeof(info), "%s: %iHP <Incapped(#%i)> [%s]", name, GetSurvivorHealth(client), (GetSurvivorIncapCount(client) + 1), info);
			}
			else
			{
				new health = GetSurvivorHealth(client) + GetSurvivorTemporaryHealth(client);
				new incapCount = GetSurvivorIncapCount(client);
				if (incapCount == 0)
				{
					Format(info, sizeof(info), "%s: %iHP [%s]", name, health, info);
				}
				else
				{
					Format(buffer, sizeof(buffer), "%i incap%s", incapCount, (incapCount > 1 ? "s" : ""));
					Format(info, sizeof(info), "%s: %iHP (%s) [%s]", name, health, buffer, info);
				}
			}
		}

		survivorCount++;
		DrawPanelText(hSpecHud, info);
	}
}

FillInfectedInfo(Handle:hSpecHud)
{
	new String:inf[128];
	new String:tank[64];
	new String:witch[64];
	if (RoundHasFlowTank())
	{
		Format(tank, sizeof(tank), "| Tank: %i%%", RoundToNearest(GetTankFlow() * 100.0));
	}
	if (RoundHasFlowWitch())
	{
		Format(witch, sizeof(witch), "| Witch: %i%%", RoundToNearest(GetWitchFlow() * 100.0));
	}
	Format(inf, sizeof(inf), "->2. Infected %s %s",tank, witch);
	DrawPanelText(hSpecHud, " ");
	DrawPanelText(hSpecHud, inf);

	decl String:info[512];
	decl String:buffer[32];
	decl String:name[MAX_NAME_LENGTH];

	new infectedCount;
	for (new client = 1; client <= MaxClients && infectedCount < GetConVarInt(z_max_player_zombies); client++)
	{
		if (!IsInfected(client))
			continue;

		GetClientFixedName(client, name, sizeof(name));
		if (!IsPlayerAlive(client))
		{
			new CountdownTimer:spawnTimer = L4D2Direct_GetSpawnTimer(client);
			new Float:timeLeft = -1.0;
			if (spawnTimer != CTimer_Null)
			{
				timeLeft = CTimer_GetRemainingTime(spawnTimer);
			}

			if (timeLeft < 0.0)
			{
				Format(info, sizeof(info), "%s: Dead", name);
			}
			else
			{
				Format(buffer, sizeof(buffer), "%is", RoundToNearest(timeLeft));
				Format(info, sizeof(info), "%s: Dead (%s)", name, (RoundToNearest(timeLeft) ? buffer : "Spawning..."));
			}
		}
		else
		{
			new L4D2SI:zClass = GetInfectedClass(client);
			if (zClass == ZC_Tank)
				continue;

			Format(info, sizeof(info), "%s: %s (%iHP)", name, ZOMBIECLASS_NAME(zClass), GetClientHealth(client));

			decl String:extra[16];
			if (IsInfectedGhost(client)) {
				extra = " [Ghost]";
			} else if (GetEntityFlags(client) & FL_ONFIRE) {
				extra = " [On Fire]";
			} else {
				extra = "";
			}
			Format(info, sizeof(info), "%s%s", info, extra);
		}

		infectedCount++;
		DrawPanelText(hSpecHud, info);
	}

	if (!infectedCount)
	{
		DrawPanelText(hSpecHud, "There are no SI at this moment.");
	}
	DrawPanelText(hSpecHud, " ");
	Format(info, sizeof(info), "Natural horde: %is", CTimer_HasStarted(L4D2Direct_GetMobSpawnTimer()) ? RoundFloat(CTimer_GetRemainingTime(L4D2Direct_GetMobSpawnTimer())) : 0);
	DrawPanelText(hSpecHud, info);
}

bool:FillTankInfo(Handle:hSpecHud, bool:bTankHUD = false)
{
	new tank = FindTank();
	if (tank == -1)
		return false;

	decl String:info[512];
	decl String:name[MAX_NAME_LENGTH];

	if (bTankHUD)
	{
		GetConVarString(FindConVar("l4d_ready_cfg_name"), info, sizeof(info));
		Format(info, sizeof(info), "%s :: Tank HUD", info);
		DrawPanelText(hSpecHud, info);
		DrawPanelText(hSpecHud, "___________________");
	}
	else
	{
		DrawPanelText(hSpecHud, " ");
		DrawPanelText(hSpecHud, "->3. Tank");
	}

	// Draw owner & pass counter
	new passCount = L4D2Direct_GetTankPassedCount();
	if (isTankControlLoaded) {
		passCount = L4D_Tank_Control_GetTankPassedCount();
	}
	switch (passCount)
	{
		case 0: Format(info, sizeof(info), "native");
		case 1: Format(info, sizeof(info), "%ist", passCount);
		case 2: Format(info, sizeof(info), "%ind", passCount);
		case 3: Format(info, sizeof(info), "%ird", passCount);
		default: Format(info, sizeof(info), "%ith", passCount);
	}

	if (!IsFakeClient(tank))
	{
		GetClientFixedName(tank, name, sizeof(name));
		Format(info, sizeof(info), "Control : %s (%s)", name, info);
	}
	else
	{
		Format(info, sizeof(info), "Control : AI (%s)", info);
	}
	DrawPanelText(hSpecHud, info);

	// Draw health
	new health = GetClientHealth(tank);
	if (health <= 0 || IsIncapacitated(tank) || !IsPlayerAlive(tank))
	{
		info = "Health  : Dead";
	}
	else
	{
		new healthPercent = RoundFloat((100.0 / (GetConVarFloat(FindConVar("z_tank_health")) * 1.5)) * health);
		Format(info, sizeof(info), "Health  : %i / %i%%", health, ((healthPercent < 1) ? 1 : healthPercent));
	}
	DrawPanelText(hSpecHud, info);

	// Draw frustration
	if (!IsFakeClient(tank))
	{
		Format(info, sizeof(info), "Frustr.  : %d%%", GetTankFrustration(tank));
	}
	else
	{
		info = "Frustr.  : AI";
	}
	DrawPanelText(hSpecHud, info);

	// Draw fire status
	if (GetEntityFlags(tank) & FL_ONFIRE)
	{
		new timeleft = RoundToCeil(health / 80.0);
		Format(info, sizeof(info), "On Fire : %is", timeleft);
		DrawPanelText(hSpecHud, info);
	}

	return true;
}
/*
FillGameInfo(Handle:hSpecHud)
{
	// Turns out too much info actually CAN be bad, funny ikr
	new tank = FindTank();
	if (tank != -1)
		return;

	DrawPanelText(hSpecHud, " ");
	DrawPanelText(hSpecHud, "->3. Game");

	decl String:info[512];
	decl String:buffer[512];

	GetConVarString(FindConVar("l4d_ready_cfg_name"), info, sizeof(info));

	if (GetCurrentGameMode() == L4D2Gamemode_Versus)
	{
		Format(info, sizeof(info), "%s (%s round)", info, (InSecondHalfOfRound() ? "2nd" : "1st"));
		DrawPanelText(hSpecHud, info);

		Format(info, sizeof(info), "Natural horde: %is", CTimer_HasStarted(L4D2Direct_GetMobSpawnTimer()) ? RoundFloat(CTimer_GetRemainingTime(L4D2Direct_GetMobSpawnTimer())) : 0);
		DrawPanelText(hSpecHud, info);

		Format(info, sizeof(info), "Survivor progress: %i%%", RoundToNearest(GetHighestSurvivorFlow() * 100.0));
		DrawPanelText(hSpecHud, info);

		if (RoundHasFlowTank())
		{
			Format(info, sizeof(info), "Tank: %i%%", RoundToNearest(GetTankFlow() * 100.0));
			DrawPanelText(hSpecHud, info);
		}

		if (RoundHasFlowWitch())
		{
			Format(info, sizeof(info), "Witch: %i%%", RoundToNearest(GetWitchFlow() * 100.0));
			DrawPanelText(hSpecHud, info);
		}
	}
	else if (GetCurrentGameMode() == L4D2Gamemode_Scavenge)
	{
		DrawPanelText(hSpecHud, info);

		new round = GetScavengeRoundNumber();
		switch (round)
		{
			case 0: Format(buffer, sizeof(buffer), "N/A");
			case 1: Format(buffer, sizeof(buffer), "%ist", round);
			case 2: Format(buffer, sizeof(buffer), "%ind", round);
			case 3: Format(buffer, sizeof(buffer), "%ird", round);
			default: Format(buffer, sizeof(buffer), "%ith", round);
		}

		Format(info, sizeof(info), "Half: %s", (InSecondHalfOfRound() ? "2nd" : "1st"));
		DrawPanelText(hSpecHud, info);

		Format(info, sizeof(info), "Round: %s", buffer);
		DrawPanelText(hSpecHud, info);
	}
}
*/

/* Stocks */

GetClientFixedName(client, String:name[], length)
{
	GetClientName(client, name, length);

	if (name[0] == '[')
	{
		decl String:temp[MAX_NAME_LENGTH];
		strcopy(temp, sizeof(temp), name);
		temp[sizeof(temp)-2] = 0;
		strcopy(name[1], length-1, temp);
		name[0] = ' ';
	}

	if (strlen(name) > 25)
	{
		name[22] = name[23] = name[24] = '.';
		name[25] = 0;
	}
}

GetRealClientCount()
{
	new clients = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && !IsFakeClient(i)) clients++;
	}
	return clients;
}

InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}

GetScavengeRoundNumber()
{
	return GameRules_GetProp("m_nRoundNumber");
}

Float:GetClientFlow(client)
{
	return (L4D2Direct_GetFlowDistance(client) / L4D2Direct_GetMapMaxFlowDistance());
}

Float:GetHighestSurvivorFlow()
{
	new Float:flow;
	new Float:maxflow = 0.0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsSurvivor(i))
		{
			flow = GetClientFlow(i);
			if (flow > maxflow)
			{
				maxflow = flow;
			}
		}
	}
	return maxflow;
}

bool:RoundHasFlowTank()
{
	return L4D2Direct_GetVSTankToSpawnThisRound(InSecondHalfOfRound());
}

bool:RoundHasFlowWitch()
{
	return L4D2Direct_GetVSWitchToSpawnThisRound(InSecondHalfOfRound());
}

Float:GetTankFlow()
{
	return L4D2Direct_GetVSTankFlowPercent(0) -
		(Float:GetConVarInt(FindConVar("versus_boss_buffer")) / L4D2Direct_GetMapMaxFlowDistance());
}

Float:GetWitchFlow()
{
	return L4D2Direct_GetVSWitchFlowPercent(0) -
		(Float:GetConVarInt(FindConVar("versus_boss_buffer")) / L4D2Direct_GetMapMaxFlowDistance());
}

bool:IsSpectator(client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 1;
}

bool:IsSurvivor(client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2;
}

bool:IsInfected(client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 3;
}

bool:IsInfectedGhost(client)
{
	return bool:GetEntProp(client, Prop_Send, "m_isGhost");
}

L4D2SI:GetInfectedClass(client)
{
	return IsInfected(client) ? (L4D2SI:GetEntProp(client, Prop_Send, "m_zombieClass")) : ZC_None;
}

FindTank()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsInfected(i) && GetInfectedClass(i) == ZC_Tank && IsPlayerAlive(i))
			return i;
	}

	return -1;
}

GetTankFrustration(tank)
{
	return (100 - GetEntProp(tank, Prop_Send, "m_frustration"));
}

bool:IsIncapacitated(client)
{
	return bool:GetEntProp(client, Prop_Send, "m_isIncapacitated");
}

bool:IsSurvivorHanging(client)
{
	return bool:(GetEntProp(client, Prop_Send, "m_isHangingFromLedge") | GetEntProp(client, Prop_Send, "m_isFallingFromLedge"));
}

GetSurvivorIncapCount(client)
{
	return GetEntProp(client, Prop_Send, "m_currentReviveCount");
}

GetSurvivorTemporaryHealth(client)
{
	new temphp = RoundToCeil(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(FindConVar("pain_pills_decay_rate")))) - 1;
	return (temphp > 0 ? temphp : 0);
}

GetSurvivorHealth(client)
{
	return GetEntProp(client, Prop_Send, "m_iHealth");
}

L4D2Gamemode:GetCurrentGameMode()
{
	static String:sGameMode[32];
	if (sGameMode[0] == EOS)
	{
		GetConVarString(FindConVar("mp_gamemode"), sGameMode, sizeof(sGameMode));
	}
	if (StrContains(sGameMode, "scavenge") > -1)
	{
		return L4D2Gamemode_Scavenge;
	}
	if (StrContains(sGameMode, "versus") > -1
		|| StrEqual(sGameMode, "mutation12")) // realism versus
	{
		return L4D2Gamemode_Versus;
	}
	else
	{
		return L4D2Gamemode_None; // Unsupported
	}
}
