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

#undef REQUIRE_PLUGIN
#include <sourceirc>

public Plugin myinfo = {
	name = "SourceIRC -> Status",
	author = "Azelphur",
	description = "Adds status and gameinfo commands show server status and who's online.",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
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

void IRC_Loaded() {
	// Call IRC_CleanUp as this function can be called more than once.
	IRC_CleanUp();
	IRC_RegCmd("status", Command_Status, "status - Shows the server name, map, nextmap, and players who are online.");
	IRC_RegCmd("gameinfo", Command_GameInfo, "gameinfo - Shows the server name, ip, map, nextmap, how many players are online and timeleft (If supported).");
}

public Action Command_GameInfo(const char[] nick, int args) {
	char hostname[256];
	GetClientName(0, hostname, sizeof(hostname));

	char serverdomain[128];
	IRC_GetServerDomain(serverdomain, sizeof(serverdomain));

	char map[64];
	GetCurrentMap(map, sizeof(map));

	char nextmap[64];
	GetNextMap(nextmap, sizeof(nextmap));

	IRC_ReplyToCommand(nick, "hostname: %s", hostname);
	IRC_ReplyToCommand(nick, "udp/ip  : %s", serverdomain);
	IRC_ReplyToCommand(nick, "map     : %s", map);
	IRC_ReplyToCommand(nick, "nextmap : %s", nextmap);
	IRC_ReplyToCommand(nick, "players : %d (%d max)", GetClientCount(), MaxClients);

	int timeleft;
	if (GetMapTimeLeft(timeleft)) {
		if (timeleft >= 0) {
			IRC_ReplyToCommand(nick, "timeleft: %d:%02d", timeleft / 60, timeleft % 60);
		}
		else {
			IRC_ReplyToCommand(nick, "timeleft: N/A");
		}
	}
	return Plugin_Handled;
}

public Action Command_Status(const char[] nick, int args) {
	char hostmask[512];
	IRC_GetHostMask(hostmask, sizeof(hostmask));

	char hostname[256];
	GetClientName(0, hostname, sizeof(hostname));

	char serverdomain[128];
	IRC_GetServerDomain(serverdomain, sizeof(serverdomain));

	char map[64];
	GetCurrentMap(map, sizeof(map));

	IRC_ReplyToCommand(nick, "hostname: %s", hostname);
	IRC_ReplyToCommand(nick, "udp/ip  : %s", serverdomain);
	IRC_ReplyToCommand(nick, "map     : %s", map);
	IRC_ReplyToCommand(nick, "players : %d (%d max)", GetClientCount(), MaxClients);

	char line[IRC_MAXLEN];
	strcopy(line, sizeof(line), "# userid name uniqueid connected ping loss state");

	bool isadmin = IRC_GetAdminFlag(hostmask, view_as<AdminFlag>ADMFLAG_GENERIC);
	if (isadmin) {
		StrCat(line, sizeof(line), " adr");
	}
	IRC_ReplyToCommand(nick, line);

	char auth[64];
	char ip[32];
	char states[32];
	int time;
	int mins;
	int secs;
	int latency;
	int loss;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientConnected(i)) {
			if (IsClientAuthorized(i)) {
				GetClientAuthId(i, AuthId_Steam2, auth, sizeof(auth));
			}
			else {
				strcopy(auth, sizeof(auth), "N/A");
			}

			if (IsClientInGame(i) && !IsFakeClient(i)) {
				time = RoundToFloor(GetClientTime(i));
				mins = time / 60;
				secs = time % 60;
				latency = RoundToFloor(GetClientAvgLatency(i, NetFlow_Both)*1000.0);
				loss = RoundToFloor(GetClientAvgLoss(i, NetFlow_Both)*100.0);
			}
			else {
				mins = 0;
				secs = 0;
				latency = -1;
				loss = -1;
			}

			if (IsClientInGame(i)) {
				strcopy(states, sizeof(states), "active");
			}
			else {
				strcopy(states, sizeof(states), "spawning");
			}

			GetClientIP(i, ip, sizeof(ip), false);

			if (isadmin) {
				Format(line, sizeof(line), "# %d \"%N\" %s %d:%02d %d %d %s %s", GetClientUserId(i), i, auth, mins, secs, latency, loss, states, ip);
			}
			else {
				Format(line, sizeof(line), "# %d \"%N\" %s %d:%02d %d %d %s", GetClientUserId(i), i, auth, mins, secs, latency, loss, states);
			}
			IRC_ReplyToCommand(nick, line);
		}
	}
	return Plugin_Handled;
}

public void OnPluginEnd() {
	IRC_CleanUp();
}

// http://bit.ly/defcon
