#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <left4downtown>
#include <l4d2_direct>

public Plugin:myinfo =
{
	name = "L4D2 Ready-Up",
	author = "CanadaRox & Blazers Team",
	description = "New and improved ready-up plugin.",
	version = "6",
	url = ""
};

enum L4D2Team
{
	L4D2Team_None = 0,
	L4D2Team_Spectator,
	L4D2Team_Survivor,
	L4D2Team_Infected
}

// Game Cvars
new Handle:god;
new Handle:sb_stop;
new Handle:liveForward;
new bool:inReadyUp;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("IsInReady", Native_IsInReady);
	liveForward = CreateGlobalForward("OnRoundIsLive", ET_Event);
	return APLRes_Success;
}
public OnPluginStart()
{
	HookEvent("round_start", RoundStart_Event, EventHookMode_Post);
	
	god = FindConVar("god");
	sb_stop = FindConVar("sb_stop");
	
	RegConsoleCmd("sm_return", Return_Cmd, "Return to a valid saferoom spawn if you get stuck");
	
	LoadTranslations("common.phrases");
	
}

public OnPluginEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

/* This ensures all cvars are reset if the map is changed during ready-up */
public OnMapEnd()
{
	if (inReadyUp)
		InitiateLive(false);
}

public Native_IsInReady(Handle:plugin, numParams)
{
	return _:inReadyUp;
}


/* No need to do any other checks since it seems like this is required no matter what since the intros unfreezes players after the animation completes */
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (inReadyUp)
	{
		if (IsClientInGame(client) && L4D2Team:GetClientTeam(client) == L4D2Team_Survivor)
		{
			if (GetEntityFlags(client) & FL_INWATER)
				ReturnPlayerToSaferoom(client, false);
		}
	}
}

public Action:L4D_OnFirstSurvivorLeftSafeArea(client)
{
	if (inReadyUp)
	{
		InitiateLive();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:Return_Cmd(client, args)
{
	ReturnPlayerToSaferoom(client, false);
	return Plugin_Handled;
}

public RoundStart_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	InitiateReadyUp();
}


InitiateReadyUp()
{
	
	inReadyUp = true;
	
	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, true);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, true);
	
	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 99999.9);
	
}

InitiateLive(bool:real = true)
{
	inReadyUp = false;

	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, false);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_stop, false);
	
	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 60.0);
	if (real)
	{
		Call_StartForward(liveForward);
		Call_Finish();
	}
	
}

ReturnPlayerToSaferoom(client, bool:flagsSet = true)
{
	new warp_flags;
	new give_flags;
	if (!flagsSet)
	{
		warp_flags = GetCommandFlags("warp_to_start_area");
		SetCommandFlags("warp_to_start_area", warp_flags & ~FCVAR_CHEAT);
		give_flags = GetCommandFlags("give");
		SetCommandFlags("give", give_flags & ~FCVAR_CHEAT);
	}

	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge"))
	{
		FakeClientCommand(client, "give health");
	}

	FakeClientCommand(client, "warp_to_start_area");

	if (!flagsSet)
	{
		SetCommandFlags("warp_to_start_area", warp_flags);
		SetCommandFlags("give", give_flags);
	}
}