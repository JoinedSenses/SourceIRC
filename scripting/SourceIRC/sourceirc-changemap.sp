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
	name = "SourceIRC -> Change Map",
	author = "Azelphur",
	description = "Adds a changemap command to SourceIRC",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
}

public void OnPluginStart() {
	LoadTranslations("sourceirc.phrases");
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
	IRC_RegAdminCmd("changemap", Command_ChangeMap, ADMFLAG_CHANGEMAP, "changemap <map> - Changes the current map, you can use a partial map name.");
}

public Action Command_ChangeMap(const char[] nick, int args) {
	char text[IRC_MAXLEN];
	IRC_GetCmdArgString(text, sizeof(text));
	if (IsMapValid(text)) {
		IRC_ReplyToCommand(nick, "%t", "Changing Map", text);
		ForceChangeLevel(text, "Requested from IRC");
	}
	else {
		char storedmap[64];
		char map[64];
		bool foundmatch;
		ArrayList maps = new ArrayList(ByteCountToCells(64));
		
		ReadMapList(maps);
		for (int i = 0; i < maps.Length; i++) {
			maps.GetString(i, storedmap, sizeof(storedmap));
			if (StrContains(storedmap, text, false) != -1) {
				if (!foundmatch) {
					strcopy(map, sizeof(map), storedmap);
					foundmatch = true;
				}
				else {
					IRC_ReplyToCommand(nick, "%t", "Multiple Maps", text);
					return Plugin_Handled;
				}
			}
		}
		if (foundmatch) {
			IRC_ReplyToCommand(nick, "%t", "Changing Map", map);
			ForceChangeLevel(map, "Requested from IRC");
			return Plugin_Handled;
		}
		else {
			IRC_ReplyToCommand(nick, "%t", "Invalid Map", text);
		}
	}
	return Plugin_Handled;
}

public void OnPluginEnd() {
	if (g_bIRC) {
		IRC_CleanUp();
	}
}

// http://bit.ly/defcon
