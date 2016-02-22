#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <left4downtown>
#include <l4d2_direct>

#define SOUND "/level/gnomeftw.wav"

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
new Handle:sb_move;
new Handle:liveForward;
new bool:inReadyUp;
new bool:blockSecretSpam[MAXPLAYERS + 1];

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
	sb_move = FindConVar("sb_move");
	
	RegConsoleCmd("sm_return", Return_Cmd, "Return to a valid saferoom spawn if you get stuck");
	RegConsoleCmd("sm_secret", Secret_Cmd, "Every player has a different secret number between 0-1023");
	
}

public OnMapStart()
{
	PrecacheSound(SOUND);
	for (new client = 1; client <= MAXPLAYERS; client++)
	{
		blockSecretSpam[client] = false;
	}
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
	if (inReadyUp)
		ReturnPlayerToSaferoom(client, false);
	else ReplyToCommand(client, "[SM] This command can only be used when nobody leaves safe area.");
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
	SetConVarBool(sb_move, false);
	
	L4D2_CTimerStart(L4D2CT_VersusStartTimer, 99999.9);
	
}

InitiateLive(bool:real = true)
{
	inReadyUp = false;

	SetConVarFlags(god, GetConVarFlags(god) & ~FCVAR_NOTIFY);
	SetConVarBool(god, false);
	SetConVarFlags(god, GetConVarFlags(god) | FCVAR_NOTIFY);
	SetConVarBool(sb_move, true);
	
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

public Action:Secret_Cmd(client, args)
{
	if (inReadyUp)
	{
		new AdminId:id;
		id = GetUserAdmin(client);
		new bool:hasFlag = false;
		if (id != INVALID_ADMIN_ID)
		{
			hasFlag = GetAdminFlag(id, Admin_Reservation); // Check for specific admin flag
		}
		
		if (!hasFlag)
		{
			ReplyToCommand(client, "[SM] Only admins can do this.");
			return Plugin_Handled;
		}
		DoSecrets(client);

		return Plugin_Handled;
		
	}
	ReplyToCommand(client, "[SM] This command can only be used when nobody leaves safe area.");
	return Plugin_Continue;
}

stock DoSecrets(client)
{
	if (L4D2Team:GetClientTeam(client) == L4D2Team_Survivor && !blockSecretSpam[client])
	{
		new particle = CreateEntityByName("info_particle_system");
		decl Float:pos[3];
		GetClientAbsOrigin(client, pos);
		pos[2] += 50;
		TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "effect_name", "achieved");
		DispatchKeyValue(particle, "targetname", "particle");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
		CreateTimer(10.0, killParticle, particle, TIMER_FLAG_NO_MAPCHANGE);
		EmitSoundToAll(SOUND, client, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.5);
		CreateTimer(2.0, SecretSpamDelay, client);
		blockSecretSpam[client] = true;
	}
}

public Action:SecretSpamDelay(Handle:timer, any:client)
{
	blockSecretSpam[client] = false;
}

public Action:killParticle(Handle:timer, any:entity)
{
	if (entity > 0 && IsValidEntity(entity) && IsValidEdict(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}