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

/**
 * NOTE: Removed Event player_changename because my servers run a name filter that prints the name to servers
 * To enable, uncomment the lines dealing with the event.
 *
 * One of the major modifications to this plugin from the original is the anti_caps_lock feature.
 */

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <regex>
#undef REQUIRE_PLUGIN
#include <sourceirc>
#include <color_literals>

bool
	  g_bShowIRC[MAXPLAYERS+1]
	, g_bLateLoad
	, g_bIRC;
ConVar
	  g_cvAllowHide
	, g_cvAllowFilter
	, g_cvHideDisconnect
	, g_cvarPctRequired
	, g_cvarMinLength
	, g_cvColor;
char
	  g_sColor[8];

public Plugin myinfo = {
	name = "SourceIRC -> Relay All",
	author = "Azelphur",
	description = "Relays various game events",
	version = IRC_VERSION,
	url = "http://azelphur.com/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	HookEvent("player_say", Event_PlayerSay, EventHookMode_Post);
	HookEvent("player_chat", Event_PlayerSay, EventHookMode_Post);

	RegConsoleCmd("sm_irc", cmdIRC, "Toggles IRC chat");
	RegAdminCmd("sm_irccolor", cmdIRCColor, ADMFLAG_ROOT, "Set IRC tag color");
	g_cvAllowHide = CreateConVar("irc_allow_hide", "0", "Sets whether players can hide IRC chat", FCVAR_NOTIFY);
	g_cvAllowFilter = CreateConVar("irc_allow_filter", "0", "Sets whether IRC filters messages beginning with !", FCVAR_NOTIFY);
	g_cvHideDisconnect = CreateConVar("irc_disconnect_filter", "0", "Sets whether IRC filters disconnect messages", FCVAR_NOTIFY);
	g_cvColor = CreateConVar("irc_color", "65bca6", "Set irc tag color");

	g_cvarPctRequired = CreateConVar("anti_caps_lock_percent", "0.9", "Force all letters to lowercase when this percent of letters is uppercase (not counting symbols)", _, true, 0.0, true, 1.0);
	g_cvarMinLength = CreateConVar("anti_caps_lock_min_length", "5", "Only force letters to lowercase when a message has at least this many letters (not counting symbols)", _, true, 0.0);

	g_cvColor.AddChangeHook(cvarColorChanged);

	LoadTranslations("sourceirc.phrases");
	g_cvColor.GetString(g_sColor, sizeof(g_sColor));
}

public Action cmdIRCColor(int client, int args) {
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));

	if (strlen(arg) != 6) {
		ReplyToCommand(client, "[IRC] Arg must be 6 hex chars");
		return Plugin_Handled;
	}
	char color[7];
	Format(color, sizeof(color), arg);
	g_cvColor.SetString(arg);

	PrintToChat(client, "\x01[\x07%sIRC\x01] Color set to\x07%s %s", arg, arg, arg);
	return Plugin_Handled;
}

public void cvarColorChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (strlen(newValue) != 6) {
		g_cvColor.SetString(oldValue);
	}
	Format(g_sColor, sizeof(g_sColor), newValue);
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

public void OnClientDisconnect(int client) {
  	g_bShowIRC[client] = true;
}

void IRC_Loaded() {
	g_bIRC = true;
	// Call IRC_CleanUp as this function can be called more than once.
	IRC_CleanUp();
	IRC_HookEvent("PRIVMSG", Event_PRIVMSG);
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	char result[IRC_MAXLEN];
	char message[256];

	result[0] = '\0';
	event.GetString("text", message, sizeof(message));
	if (g_cvAllowFilter.BoolValue && message[0] == '!') {
		return Plugin_Continue;
	}
	if (client != 0 && !IsPlayerAlive(client)) {
		StrCat(result, sizeof(result), "* ");
	}

	int letters;
	int uppercase;
	int length = strlen(message);
	// -- Anti-caps
	for (int i; i < length; i++) {
		if (message[i] >= 'A' && message[i] <= 'Z') {
			uppercase++;
			letters++;
		}
		else if (message[i] >= 'a' && message[i] <= 'z') {
			letters++;
		}
	}
	if (letters >= g_cvarMinLength.IntValue && float(uppercase) / float(letters) >= g_cvarPctRequired.FloatValue) {
		
		for (int i; i < length; i++) {
			if (message[i] >= 'A' && message[i] <= 'Z') {
				message[i] = CharToLower(message[i]);
			}
		}
	}
	// --------
	int team;
	team = client ? IRC_GetTeamColor(GetClientTeam(client)) : 0;
	char clientname[MAX_NAME_LENGTH];
	Format(clientname, sizeof(clientname), "%N", client);
	ReplaceString(clientname, sizeof(clientname), ":", "ː");
	if (team == -1) {
		Format(result, sizeof(result), "%s%s: %s", result, clientname, message);
	}
	else {
		Format(result, sizeof(result), "\x03%02d%s%s\x03: %s", team, result, clientname, message);
	}

	IRC_MsgFlaggedChannels("relay", "%s", result);
	return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if (g_cvHideDisconnect.BoolValue) {
		return Plugin_Handled;
	}
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if (client != 0) {
		char reason[128];
		char playername[MAX_NAME_LENGTH];
		char auth[64];
		char result[IRC_MAXLEN];

		event.GetString("reason", reason, sizeof(reason));
		GetClientName(client, playername, sizeof(playername));
		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
		// For some reason, certain disconnect reasons have \n in them, so i'm stripping them. Silly valve.
		for (int i; i <= strlen(reason); i++) {
			if (reason[i] == '\n') {
				RemoveChar(reason, sizeof(reason), i);
			}
		}
		Format(result, sizeof(result), "%t", "Player Disconnected", playername, auth, userid, reason);
		if (result[0] != '\0') {
			IRC_MsgFlaggedChannels("relay", "%s", result);
		}
	}
	return Plugin_Continue;
}

public void OnMapEnd() {
	g_bLateLoad = false;
	IRC_MsgFlaggedChannels("relay", "%t", "Map Changing");
}

public void OnMapStart() {
	for (int i = 1; i <= MaxClients; i++) {
        g_bShowIRC[i] = true;
    }
	if (g_bLateLoad) {
		return;
	}
	char map[128];
	GetCurrentMap(map, sizeof(map));
	IRC_MsgFlaggedChannels("relay", "%t", "Map Changed", map);
}

public Action Event_PRIVMSG(const char[] hostmask, int args) {
	char channel[64];
	IRC_GetEventArg(1, channel, sizeof(channel));
	if (!IRC_ChannelHasFlag(channel, "relay")) {
		return Plugin_Handled;
	}
	char nick[IRC_NICK_MAXLEN];
	char text[IRC_MAXLEN];

	IRC_GetNickFromHostMask(hostmask, nick, sizeof(nick));
	IRC_GetEventArg(2, text, sizeof(text));

	if (!strncmp(text, "\x01ACTION ", 8) && text[strlen(text)-1] == '\x01') {
		text[strlen(text)-1] = '\x00';
		// Strip IRC Color Codes
		IRC_Strip(text, sizeof(text));
		// Strip Game color codes
		IRC_StripGame(text, sizeof(text));

		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && g_bShowIRC[i]) {
				PrintColoredChat(i, "[\x03IRC\x01] * %s %s", nick, text[7]);
			}
		}
	}
	else {
		bool isPlayer;
		char colorValue[3];
		char color[9];
		if (text[0] == '\x03') {
			isPlayer = true;
			strcopy(colorValue, sizeof(colorValue), text[1]);
			int value = StringToInt(colorValue);
			switch(value) {
				case 0: {
					color = "\x07edfcff";
				}
				case 1: {
					color = "\x07000000";
				}
				case 2: {
					color = "\x070000bc";
				}
				case 3: {
					color = "\x07009300";
				}
				case 4: {
					color = "\x07ff4444";
				}
				case 5: {
					color = "\x077f0000";
				}
				case 6: {
					color = "\x079c009c";
				}
				case 7: {
					color = "\x07fc7f00";
				}
				case 8: {
					color = "\x07FFFF00";
				}
				case 9: {
					color = "\x0700d600";
				}
				case 10: {
					color = "\x07009393";
				}
				case 11: {
					color = "\x0700cccc";
				}
				case 12: {
					color = "\x0799CCFF";
				}
				case 13: {
					color = "\x07ff00ff";
				}
				case 14: {
					color = "\x077f7f7f";
				}
				case 15: {
					color = "\x07cbd1cf";
				}
			}
		}

		// Strip IRC Color Codes
		IRC_Strip(text, sizeof(text));
		// Strip Game color codes
		IRC_StripGame(text, sizeof(text));

		char message[2][IRC_MAXLEN];
		int explode = ExplodeString(text, ":", message, 2, IRC_MAXLEN, true);
	
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && g_bShowIRC[i]) {
				if (explode != 1 && isPlayer) {
					PrintColoredChat(i, "\x07%s%s\x01| %s%s\x01:%s", g_sColor, nick, color, message[0], message[1]);
				}
				else {
					ReplaceString(text, sizeof(text), "__", "");
					ReplaceString(text, sizeof(text), "**", "");
					PrintColoredChat(i, "[\x07%sIRC\x01] \x07d0e8f4%s\x01 :  %s", g_sColor, nick, text);
				}
			}
		}
	}
	return Plugin_Handled;
}

public Action cmdIRC(int client, int iArgC) {
	if (client == 0) {
		return Plugin_Handled;
	}
	if (g_cvAllowHide.BoolValue) {
		// Flip boolean
		g_bShowIRC[client] = !g_bShowIRC[client];
		PrintColoredChat(client, "[\x03IRC\x01] %s listening to IRC chat", g_bShowIRC[client] ? "Now" : "Stopped");
    }
	else {
		PrintColoredChat(client, "[\x03IRC\x01] IRC Hide not allowed for this server");
	}
	return Plugin_Handled;
}

public void OnPluginEnd() {
	if (g_bIRC) {
		IRC_CleanUp();
	}
}