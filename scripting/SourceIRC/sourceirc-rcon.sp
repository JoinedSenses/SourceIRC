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
#include <socket>
#undef REQUIRE_PLUGIN
#include <sourceirc>
#define SERVERDATA_EXECCOMMAND 2
#define SERVERDATA_AUTH 3

Handle
	gsocket;
int
	REQUESTID;
bool
	busy;
char
	greplynick[64]
	, gcommand[256];

public Plugin myinfo = {
	name = "SourceIRC -> RCON",
	author = "Azelphur",
	description = "Allows you to run RCON commands",
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
	IRC_RegAdminCmd("rcon", Command_RCON, ADMFLAG_RCON, "rcon <command> - Run an rcon command on the server.");
}

public Action Command_RCON(const char[] nick, int args) {
	if (busy) {
		IRC_ReplyToCommand(nick, "%t", "RCON Busy");
	}
	else {
		IRC_GetCmdArgString(gcommand, sizeof(gcommand));
		strcopy(greplynick, sizeof(greplynick), nick);
		Connect();
	}
	return Plugin_Handled;
}

void Connect() {
	char ServerIp[16];
	int iIp = FindConVar("hostip").IntValue;
	Format(ServerIp, sizeof(ServerIp), "%i.%i.%i.%i", (iIp >> 24) & 0x000000FF,
                                                      (iIp >> 16) & 0x000000FF,
                                                      (iIp >>  8) & 0x000000FF,
                                                      (iIp >>  0) & 0x000000FF);
	int ServerPort = FindConVar("hostport").IntValue;
	gsocket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketConnect(gsocket, OnSocketConnect, OnSocketReceive, OnSocketDisconnected, ServerIp, ServerPort);
}

public void OnSocketConnect(Handle socket, any arg) {
	char rcon_password[256];
	FindConVar("rcon_password").GetString(rcon_password, sizeof(rcon_password));
	if (StrEqual(rcon_password, "")) {
		SetFailState("You need to enable RCON to use this plugin");
	}
	// Escape out any percent symbols that should happen to be in the password
	ReplaceString(rcon_password, sizeof(rcon_password), "%", "%%");
	Send(SERVERDATA_AUTH, rcon_password);
}

public void OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile) {
	int i = 0;
	while (i < dataSize) {
		int
			packetlen = ReadByte(receiveData[i])
			, requestid = ReadByte(receiveData[i+4])
			, serverdata = ReadByte(receiveData[i+8]);

		if (serverdata == 2) {
			if (requestid == 1) {
				Send(SERVERDATA_EXECCOMMAND, gcommand);
			}
			else {
				IRC_ReplyToCommand(greplynick, "Unable to connect to RCON");
			}
		}
		if (serverdata == 0 && requestid > 1) {
			char lines[64][256];
			int linecount = ExplodeString(receiveData[i+12], "\n", lines, sizeof(lines), sizeof(lines[]));
			for (int l; l < linecount; l++) {
				IRC_ReplyToCommand(greplynick, "%s", lines[l]);
			}
			busy = false;
			SocketDisconnect(gsocket);
			REQUESTID = 0;
			delete socket;
		}
		i += packetlen+4;
	}
}

public void OnSocketDisconnected(Handle socket, any hFile) {
	REQUESTID = 0;
	delete socket;
}

public void OnSocketError(Handle socket, const int errorType, const int errorNum, any hFile) {
	LogError("socket error %d (errno %d)", errorType, errorNum);
	delete socket;
}

int ReadByte(char[] recieveData) {
	int
		numbers[4]
		, number;

	for (int i; i <= 3; i++) {
		numbers[i] = recieveData[i];
	}
	number += numbers[0];
	number += numbers[1]<<8;
	number += numbers[2]<<16;
	number += numbers[3]<<24;
	return number;
}

void Send(int type, const char[] format, any ...) {
	REQUESTID++;
	char
		packet[1024]
		, command[1014];

	VFormat(command, sizeof(command), format, 2);
	int num = strlen(command)+10;
	Format(packet, sizeof(packet), "%c%c%c%c%c%c%c%c%c%c%c%c%s\x00\x00", num&0xFF, num >> 8&0xFF, num >> 16&0xFF, num >> 24&0xFF, REQUESTID&0xFF, REQUESTID >> 8&0xFF, REQUESTID >> 16&0xFF, REQUESTID >> 24&0xFF, type&0xFF, type >> 8&0xFF, type >> 16&0xFF, type >> 24&0xFF, command);
	SocketSend(gsocket, packet, strlen(command)+14);
}

public void OnPluginEnd() {
	IRC_CleanUp();
}

// http://bit.ly/defcon
