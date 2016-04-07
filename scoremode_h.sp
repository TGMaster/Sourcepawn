#include <sourcemod>
#include <colors>
#undef REQUIRE_PLUGIN
#include <l4d2_scoremod>
#include <scoremod2>
#define REQUIRE_PLUGIN

#define L4D2_ScoreMod 1
#define ScoreMod2 2

new scoremode;

public Plugin:myinfo =
{
	name = "Print Health Bonus to Chat Command",
	author = "darkid, Blazers Team",
	description = "Print Health Bonus to Chat Command",
	version = "1.0",
	url = "https://github.com/TGMaster/Scripting"
};

public OnPluginStart()
{
	RegConsoleCmd("sm_h", Cmd_PrintHB, "Prints Bonus");
}

public OnAllPluginsLoaded()
{
	if (LibraryExists("l4d2_scoremod")) {
		scoremode |= L4D2_ScoreMod;
	}
	if (LibraryExists("scoremod2")) {
		scoremode |= ScoreMod2;
	}
}
public OnLibraryRemoved(const String:name[])
{
	if (strcmp(name, "l4d2_scoremod") == 0) {
		scoremode &= ~L4D2_ScoreMod;
	} else if (strcmp(name, "scoremod2") == 0) {
		scoremode &= ~ScoreMod2;
	}
}
public OnLibraryAdded(const String:name[])
{
	if (strcmp(name, "l4d2_scoremod") == 0) {
		scoremode |= L4D2_ScoreMod;
	} else if (strcmp(name, "scoremod2") == 0) {
		scoremode |= ScoreMod2;
	}
}

public Action:Cmd_PrintHB (client, args)
{
	decl String:type[32];
	new bonus;
	if (scoremode & L4D2_ScoreMod == L4D2_ScoreMod) {
		type = "Health";
		bonus = HealthBonus();
	} else if (scoremode & ScoreMod2 == ScoreMod2) {
		type = "Damage";
		bonus = DamageBonus();
	} else {
		return;
	}
	CPrintToChat(client, "{blue}[{default}Score{blue}]{default} %s Bonus: {blue}%d", type, bonus);
}