#include <sourcemod>
#include <sdktools>
#include <colors>

#define VOICE_NORMAL	0	/**< Allow the client to listen and speak normally. */
#define VOICE_MUTED		1	/**< Mutes the client from speaking to everyone. */
#define VOICE_SPEAKALL	2	/**< Allow the client to speak to everyone. */
#define VOICE_LISTENALL	4	/**< Allow the client to listen to everyone. */
#define VOICE_TEAM		8	/**< Allow the client to always speak to team, even when dead. */
#define VOICE_LISTENTEAM	16	/**< Allow the client to always hear teammates, including dead ones. */

#define TEAM_SPEC 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

new Handle:hAllTalk;


#define PLUGIN_VERSION "2.2"
public Plugin:myinfo = 
{
	name = "SpecLister",
	author = "waertf & bear modded by bman & Blazers Team",
	description = "Allows spectator listen others team voice for l4d",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=95474"
}


 public OnPluginStart()
{
	HookEvent("player_team",Event_PlayerChangeTeam);
	RegConsoleCmd("hear", Panel_hear);
	
	//Fix for End of round all-talk.
	hAllTalk = FindConVar("sv_alltalk");
	HookConVarChange(hAllTalk, OnAlltalkChange);
	
	//Spectators hear Team_Chat
	AddCommandListener(Command_SayTeam, "say_team");

}
public PanelHandler1(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		PrintToConsole(param1, "You selected item: %d", param2)
		if(param2==1)
		{
			SetClientListeningFlags(param1, VOICE_LISTENALL);
			PrintToChat(param1,"\x03[Voice] \x01You have \x04Enabled \x01voice listen." );
		}
		else
		{
			SetClientListeningFlags(param1, VOICE_NORMAL);
			PrintToChat(param1,"\x03[Voice] \x01You have \x04Disabled \x01voice listen." );
		}
		
	}
	else if (action == MenuAction_Cancel) {
		PrintToServer("Client %d's menu was cancelled.  Reason: %d", param1, param2);
	}
}


public Action:Panel_hear(client,args)
{
	if(GetClientTeam(client)!=TEAM_SPEC)
		return Plugin_Handled;
	new Handle:panel = CreatePanel();
	SetPanelTitle(panel, "Enable listen mode ?");
	DrawPanelItem(panel, "Yes");
	DrawPanelItem(panel, "No");
 
	SendPanelToClient(panel, client, PanelHandler1, 20);
 
	CloseHandle(panel);
 
	return Plugin_Handled;

}

public Action:Command_SayTeam(client, const char[] command, args)
{
	char text[4096];
	GetCmdArgString(text, sizeof(text));
	new senderteam = GetClientTeam(client);
	
	/*
	if(FindCharInString(text, '@') == 0)	//Check for admin messages
		return Plugin_Continue;
	if(text[1] == '!' || text[1] == '/')	// Hidden command or chat trigger
		return Plugin_Continue;
	new startidx = trim_quotes(text);  //Not sure why this function is needed.(bman)
	*/
	
	StripQuotes(text);
	if (IsChatTrigger() && text[0] == '/' || text[0] == '!' || text[0] == '@')  // Hidden command or chat trigger
	{
		return Plugin_Continue;
	}
	
	char senderTeamName[10];
	switch (senderteam)
	{
		case 3:
			senderTeamName = "Infected"
		case 2:
			senderTeamName = "Survivor"
		case 1:
			senderTeamName = "SPEC"
	}
	
	//Is not console, Sender is not on Spectators, and there are players on the spectator team
	if (client == 0)
		PrintToChatAll("Console : %s", text);
	else if (senderteam != TEAM_SPEC && GetTeamClientCount(TEAM_SPEC) > 0)
	{
		for (new i = 1; i <= GetMaxClients(); i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SPEC)
			{
				//Format(buffermsg, 256, "{default}(%s) {teamcolor}%s{olive} :  %s", senderTeamName, name, text[startidx]);
				//Format(buffermsg, 256, "\x01(TEAM-%s) \x03%s\x05: %s", senderTeamName, name, text[startidx]);
				//CPrintToChatEx(i, client, buffermsg);	//Send the message to spectators
				
				CPrintToChatEx(i, client, "{default}(%s) {teamcolor}%N{default} : {olive} %s", senderTeamName, client, text);
			}
		}
	}
	return Plugin_Continue;
}
/*
public trim_quotes(String:text[])
{
	new startidx = 0
	if (text[0] == '"')
	{
		startidx = 1
		// Strip the ending quote, if there is one
		new len = strlen(text);
		if (text[len-1] == '"')
		{
			text[len-1] = '\0'
		}
	}
	
	return startidx
}
*/
public Event_PlayerChangeTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new userTeam = GetEventInt(event, "team");
	if(client==0)
		return ;

	//PrintToChat(userID,"\x02X02 \x03X03 \x04X04 \x05X05 ");\\ \x02:color:default \x03:lightgreen \x04:orange \x05:darkgreen
	
	if(userTeam==TEAM_SPEC && IsValidClient(client))
	{
		SetClientListeningFlags(client, VOICE_NORMAL);
	}
	else
	{
		SetClientListeningFlags(client, VOICE_NORMAL);
	}
}
	
public OnAlltalkChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (StringToInt(newValue) == 0)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && GetClientTeam(i) == TEAM_SPEC)
			{
				SetClientListeningFlags(i, VOICE_LISTENALL);
				//PrintToChat(i,"Re-Enable Listen Because of All-Talk");
			}
		}
	}
}

public OnClientDisconnect(client)
{
	if(IsClientInGame(client)) {
		if (!IsFakeClient(client) && GetClientTeam(client) != 1)	//Make the choose team menu display when someone quits
		{
			for (new i = 1; i <= MaxClients; i++)
			{
				if (IsClientInGame(i)) {
					if (IsValidClient(i) && GetClientTeam(i) == 1)
					{
						ClientCommand(i, "chooseteam");
					}
				}
			}
		}
	}
}

public IsValidClient (client)
{
    if (client == 0)
        return false;
    
    if (!IsClientConnected(client))
        return false;
    
    if (IsFakeClient(client))
        return false;
    
    if (!IsClientInGame(client))
        return false;	
		
    return true;
} 
