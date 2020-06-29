/*
       This file is part of SourceIRC.

    SourceIRC is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SourceIRC is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with SourceIRC.  If not, see <http://www.gnu.org/licenses/>.
*/

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 65535

#include <sourcemod>
#undef REQUIRE_PLUGIN
#include <sourceirc>

bool g_bIRC;

public Plugin myinfo = {
	name = "SourceIRC -> Ban",
	author = "Azelphur",
	description = "Adds ban command to SourceIRC",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
}

public void OnPluginStart() {
	LoadTranslations("common.phrases");
	LoadTranslations("plugin.basecommands");
}

public void OnAllPluginsLoaded() {
	if (LibraryExists("sourceirc")) {
		IRC_Loaded();
	}
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "sourceirc")) {
		IRC_Loaded();
	}
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "sourceirc")) {
		g_bIRC = false;
	}
}

void IRC_Loaded() {
	g_bIRC = true;
	// Call IRC_CleanUp as this function can be called more than once.
	IRC_CleanUp();
	IRC_RegAdminCmd("ban", Command_Ban, ADMFLAG_BAN, "ban <#userid|name> <minutes|0> [reason] - Bans a player from the server");
}

public Action Command_Ban(const char[] nick, int args) {
	// Blatently borrowed code from basebans/bans
	if (args < 2) {
		IRC_ReplyToCommand(nick, "Usage: ban <#userid|name> <minutes|0> [reason]");
		return Plugin_Handled;
	}
	int len;
	int next_len;
	char Arguments[256];
	char arg[65];
	char s_time[12];

	IRC_GetCmdArgString(Arguments, sizeof(Arguments));
	len = BreakString(Arguments, arg, sizeof(arg));
	int target = IRC_FindTarget(nick, arg, true);
	if (target == -1) {
		return Plugin_Handled;
	}
	if ((next_len = BreakString(Arguments[len], s_time, sizeof(s_time))) != -1) {
		len += next_len;
	}
	else {
		len = 0;
		Arguments[0] = '\0';
	}
	int time = StringToInt(s_time);

	PrepareBan(nick, target, time, Arguments[len]);

	return Plugin_Handled;
}

void PrepareBan(const char[] nick, int target, int time, const char[] reason) {
	char authid[64];
	char name[32];
	char hostmask[IRC_MAXLEN];
	
	GetClientAuthId(target, AuthId_Steam2, authid, sizeof(authid));
	GetClientName(target, name, sizeof(name));

	if (!time) {
		if (reason[0] == '\0') {
			IRC_ReplyToCommand(nick, "%t", "Permabanned player", name);
		}
		else {
			IRC_ReplyToCommand(nick, "%t", "Permabanned player reason", name, reason);
		}
	}
	else {
		if (reason[0] == '\0') {
			IRC_ReplyToCommand(nick, "%t", "Banned player", name, time);
		}
		else {
			IRC_ReplyToCommand(nick, "%t", "Banned player reason", name, time, reason);
		}
	}

	IRC_GetHostMask(hostmask, sizeof(hostmask));
	LogAction(-1, target, "\"%s\" banned \"%L\" (minutes \"%d\") (reason \"%s\")", hostmask, target, time, reason);

	if (reason[0] == '\0') {
		BanClient(target, time, BANFLAG_AUTO, "Banned", "Banned", "sourceirc_ban", 0);
	}
	else {
		BanClient(target, time, BANFLAG_AUTO, reason, reason, "sourceirc_ban", 0);
	}
}

public void OnPluginEnd() {
	if (g_bIRC) {
		IRC_CleanUp();
	}
}

// http://bit.ly/defcon
