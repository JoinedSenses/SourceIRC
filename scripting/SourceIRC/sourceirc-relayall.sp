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
#include <regex>
#undef REQUIRE_PLUGIN
#include <sourceirc>

int
	g_userid;
bool
	g_bIsTeam
	, g_bShowIRC[MAXPLAYERS+1];
ConVar
	g_cvAllowHide
	, g_cvAllowFilter
	, g_cvHideDisconnect
	, g_cvarPctRequired
	, g_cvarMinLength;

public Plugin myinfo = {
	name = "SourceIRC -> Relay All",
	author = "Azelphur",
	description = "Relays various game events",
	version = IRC_VERSION,
	url = "http://azelphur.com/"
}

public void OnPluginStart() {
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Post);
	//HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Post);
	HookEvent("player_say", Event_PlayerSay, EventHookMode_Post);
	HookEvent("player_chat", Event_PlayerSay, EventHookMode_Post);

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say2", Command_Say);
	RegConsoleCmd("say_team", Command_SayTeam);
	RegConsoleCmd("sm_irc", cmdIRC, "Toggles IRC chat");
	g_cvAllowHide = CreateConVar("irc_allow_hide", "0", "Sets whether players can hide IRC chat", FCVAR_NOTIFY);
	g_cvAllowFilter = CreateConVar("irc_allow_filter", "0", "Sets whether IRC filters messages beginning with !", FCVAR_NOTIFY);
	g_cvHideDisconnect = CreateConVar("irc_disconnect_filter", "0", "Sets whether IRC filters disconnect messages", FCVAR_NOTIFY);

	g_cvarPctRequired = CreateConVar("anti_caps_lock_percent", "0.9", "Force all letters to lowercase when this percent of letters is uppercase (not counting symbols)", _, true, 0.0, true, 1.0);
	g_cvarMinLength = CreateConVar("anti_caps_lock_min_length", "5", "Only force letters to lowercase when a message has at least this many letters (not counting symbols)", _, true, 0.0);

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

public void OnClientDisconnect(int client) {
  	g_bShowIRC[client] = true;
}

void IRC_Loaded() {
	// Call IRC_CleanUp as this function can be called more than once.
	IRC_CleanUp();
	IRC_HookEvent("PRIVMSG", Event_PRIVMSG);
}

public Action Command_Say(int client, int args) {
	// Ugly hack to get around player_chat event not working.
	g_bIsTeam = false;
}

public Action Command_SayTeam(int client, int args) {
	// Ugly hack to get around player_chat event not working.
	g_bIsTeam = true;
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast) {
	int
		userid = event.GetInt("userid")
		, client = GetClientOfUserId(userid);

	char
		result[IRC_MAXLEN]
		, message[256];

	result[0] = '\0';
	event.GetString("text", message, sizeof(message));
	if (g_cvAllowFilter.BoolValue) {
		if (message[0] == '!') {
			return Plugin_Continue;
		}
	}
	if (client != 0 && !IsPlayerAlive(client)) {
		StrCat(result, sizeof(result), "*DEAD* ");
	}
	if (g_bIsTeam) {
		StrCat(result, sizeof(result), "(TEAM) ");
	}

	int
		letters
		, uppercase
		, length = strlen(message);

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
		// Force to lowercase
		for (int i; i < length; i++) {
			if (message[i] >= 'A' && message[i] <= 'Z') {
				message[i] = CharToLower(message[i]);
			}
		}
	}
	int team;
	if (client != 0) {
		team = IRC_GetTeamColor(GetClientTeam(client));
	}
	else {
		team = 0;
	}
	if (team == -1) {
		Format(result, sizeof(result), "%s%N: %s", result, client, message);
	}
	else {
		Format(result, sizeof(result), "%s\x03%02d%N\x03: %s", result, team, client, message);
	}

	IRC_MsgFlaggedChannels("relay", result);
	return Plugin_Continue;
}


// We are hooking this instead of the player_connect event as we want the steamid
public void OnClientPutInServer(int client) {
	int userid = GetClientUserId(client);
	char auth[64];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	if (IsFakeClient(client)) {
		return;
	}
	// Ugly hack to get around mass connects on map change
	if (userid <= g_userid) {
		return;
	}
	g_userid = userid;
	char
		playername[MAX_NAME_LENGTH]
		, result[IRC_MAXLEN];

	GetClientName(client, playername, sizeof(playername));
	Format(result, sizeof(result), "%t", "Player Connected", playername, auth, userid);
	if (!StrEqual(result, "")) {
		IRC_MsgFlaggedChannels("relay", result);
	}
	return;
}


public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if (!g_cvHideDisconnect.BoolValue) {
		int
			userid = event.GetInt("userid")
			, client = GetClientOfUserId(userid);
		if (client != 0) {
			char
				reason[128]
				, playername[MAX_NAME_LENGTH]
				, auth[64]
				, result[IRC_MAXLEN];

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
			if (!StrEqual(result, "")) {
				IRC_MsgFlaggedChannels("relay", result);
			}
		}
	}
}

//public Action Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
//{
//	new userid = event.GetInt("userid");
//	new client = GetClientOfUserId(userid);
//	if (client != 0) {
//		char oldname[128], char newname[MAX_NAME_LENGTH], char auth[64], char result[IRC_MAXLEN];
//		event.GetString("oldname", oldname, sizeof(oldname));
//		event.GetString("newname", newname, sizeof(newname));
//		GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
//		Format(result, sizeof(result), "%t", "Changed Name", oldname, auth, userid, newname);
//		if (StrEqual(oldname, newname))
//		{
//			return Plugin_Continue;
//		}
//		if (!StrEqual(result, ""))
//			IRC_MsgFlaggedChannels("relay", result);
//	}
//}

public void OnMapEnd() {
	IRC_MsgFlaggedChannels("relay", "%t", "Map Changing");
}

public void OnMapStart() {
	for (int i = 1; i <= MAXPLAYERS; i++) {
        g_bShowIRC[i] = true;
    }

	char map[128];
	GetCurrentMap(map, sizeof(map));
	IRC_MsgFlaggedChannels("relay", "%t", "Map Changed", map);
}

public Action Event_PRIVMSG(const char[] hostmask, int args) {
	char channel[64];
	IRC_GetEventArg(1, channel, sizeof(channel));
	if (IRC_ChannelHasFlag(channel, "relay")) {
		char
			nick[IRC_NICK_MAXLEN]
			, text[IRC_MAXLEN];

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
				PrintToChat(i, "\x01[\x03IRC\x01] * %s %s", nick, text[7]);
				}
			}
		}
		else {
			// Strip IRC Color Codes
			IRC_Strip(text, sizeof(text));
			// Strip Game color codes
			IRC_StripGame(text, sizeof(text));

			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientInGame(i) && !IsFakeClient(i) && g_bShowIRC[i]) {
				PrintToChat(i, "\x01[\x03IRC\x01] %s :  %s", nick, text);
				}
			}
		}
	}
}

public Action cmdIRC(int client, int iArgC) {
	if (g_cvAllowHide.BoolValue) {
		// Flip boolean
		g_bShowIRC[client] = !g_bShowIRC[client];
		ReplyToCommand(client, "[SourceIRC] %s listening to IRC chat", g_bShowIRC[client] ? "Now" : "Stopped");
    }
	else {
		PrintToChat(client, "\x01[\x03IRC\x01] IRC Hide not allowed for this server");
	}
	return Plugin_Handled;
}

public void OnPluginEnd() {
	IRC_CleanUp();
}

// http://bit.ly/defcon
