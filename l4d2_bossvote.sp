/*
	SourcePawn is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	SourceMod is Copyright (C) 2006-2008 AlliedModders LLC.  All rights reserved.
	Pawn and SMALL are Copyright (C) 1997-2008 ITB CompuPhase.
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

#include <sourcemod>
#include <builtinvotes>
#include <l4d2_direct>
#define REQUIRE_PLUGIN
#include <bosspercent>
#include <readyup>
#include <colors>

new Handle:hVote;

new Float:fTankFlow;
new Float:fWitchFlow;

new String:tank[8];
new String:witch[8];

public Plugin:myinfo =
{
	name = "L4D2 Boss Percents Vote",
	author = "Visor",
	version = "1.0",
	description = "Vote for percentage",
	url = "https://github.com/Attano/Equilibrium"
};

public OnPluginStart()
{
	//HookEvent("round_start", EventHook:OnRoundStart, EventHookMode_PostNoCopy);
	RegConsoleCmd("sm_voteboss", Vote);
}

public Action:Vote(client, args) 
{
	if (args < 1)
	{
		CPrintToChat(client, "{blue}[{default}BossVote{blue}]{default} Usage: {green}!voteboss{olive} <tank> <witch>");
		CPrintToChat(client, "{blue}[{default}BossVote{blue}]{default} Example: {green}!voteboss{default} 70 50");
		return Plugin_Handled;
	}
	GetCmdArg(1, tank, sizeof(tank));
	fTankFlow = StringToFloat(tank) / 100.0;
	GetCmdArg(2, witch, sizeof(witch));
	fWitchFlow = StringToFloat(witch) / 100.0;
	
	if (IsSpectator(client) || !IsInReady() || InSecondHalfOfRound())
	{
		CPrintToChat(client, "{blue}[{default}BossVote{blue}]{default} Vote can only be started by a player during ready-up @ first round!");
		return Plugin_Handled;
	}

	if (StartVote(client, "Change the percentage of tank and witch spawn?"))
		FakeClientCommand(client, "Vote Yes");

	return Plugin_Handled; 
}

bool:StartVote(client, const String:sVoteHeader[])
{
	if (IsNewBuiltinVoteAllowed())
	{
		new iNumPlayers;
		decl players[MaxClients];
		for (new i = 1; i <= MaxClients; i++)
		{
			if (!IsClientConnected(i) || !IsClientInGame(i)) continue;
			if (IsSpectator(i) || IsFakeClient(i)) continue;
			
			players[iNumPlayers++] = i;
		}
		
		hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		SetBuiltinVoteArgument(hVote, sVoteHeader);
		SetBuiltinVoteInitiator(hVote, client);
		SetBuiltinVoteResultCallback(hVote, VoteResultHandler);
		DisplayBuiltinVote(hVote, players, iNumPlayers, 20);
		return true;
	}

	CPrintToChat(client, "{blue}[{default}BossVote{blue}]{default} Vote cannot be started now.");
	return false;
}

public VoteActionHandler(Handle:vote, BuiltinVoteAction:action, param1, param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			hVote = INVALID_HANDLE;
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, BuiltinVoteFailReason:param1);
		}
	}
}

public VoteResultHandler(Handle:vote, num_votes, num_clients, const client_info[][2], num_items, const item_info[][2])
{
	for (new i = 0; i < num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_clients / 2))
			{
				DisplayBuiltinVotePass(vote, "Applying custom boss spawns...");
				PrintToChatAll("\x01[\x03BossVote\x01] Vote passed! Applying custom boss spawns...");
				CreateTimer(3.0, RewriteBossFlows);
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

/*public OnRoundStart()
{
	CreateTimer(5.5, RewriteBossFlows);
}*/

public Action:RewriteBossFlows(Handle:timer)
{
	if (!InSecondHalfOfRound())
	{
		SetTankSpawn(fTankFlow);
		SetWitchSpawn(fWitchFlow);
		UpdateBossPercents();
	}
}

SetTankSpawn(Float:flow)
{
	for (new i = 0; i <= 1; i++)
	{
		if (flow != 0)
		{
			L4D2Direct_SetVSTankToSpawnThisRound(i, true);
			L4D2Direct_SetVSTankFlowPercent(i, flow);
		}
		else
		{
			L4D2Direct_SetVSTankToSpawnThisRound(i, false);
		}
	}
}

SetWitchSpawn(Float:flow)
{
	for (new i = 0; i <= 1; i++)
	{
		if (flow != 0)
		{
			L4D2Direct_SetVSWitchToSpawnThisRound(i, true);
			L4D2Direct_SetVSWitchFlowPercent(i, flow);
		}
		else
		{
			L4D2Direct_SetVSWitchToSpawnThisRound(i, false);
		}
	}
}

stock bool:IsSpectator(client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 1;
}

stock InSecondHalfOfRound()
{
	return GameRules_GetProp("m_bInSecondHalfOfRound");
}
