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

#include <sourcemod>
#include <socket>
#undef REQUIRE_PLUGIN
#include <sourceirc>
#define SERVERDATA_EXECCOMMAND 2
#define SERVERDATA_AUTH 3

Socket g_hSocket;
int g_iRequestId;
bool g_bBusy;
char g_sReplyNick[64];
char g_sCommand[256];
bool g_bIRC;

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

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "sourceirc")) {
		g_bIRC = false;
	}
}

void IRC_Loaded() {
	g_bIRC = true;
	// Call IRC_CleanUp as this function can be called more than once.
	IRC_CleanUp();
	IRC_RegAdminCmd("rcon", Command_RCON, ADMFLAG_RCON, "rcon <command> - Run an rcon command on the server.");
}

public Action Command_RCON(const char[] nick, int args) {
	if (g_bBusy) {
		IRC_ReplyToCommand(nick, "%t", "RCON Busy");
	}
	else {
		IRC_GetCmdArgString(g_sCommand, sizeof(g_sCommand));
		strcopy(g_sReplyNick, sizeof(g_sReplyNick), nick);
		Connect();
	}
	return Plugin_Handled;
}

void Connect() {
	char ServerIp[16];
	int iIp = FindConVar("hostip").IntValue;
	FormatEx(
		ServerIp,
		sizeof(ServerIp),
		"%i.%i.%i.%i",
		(iIp >> 24) & 0x000000FF,
		(iIp >> 16) & 0x000000FF,
		(iIp >>  8) & 0x000000FF,
		(iIp >>  0) & 0x000000FF
	);

	int ServerPort = FindConVar("hostport").IntValue;
	g_hSocket = new Socket(SOCKET_TCP, OnSocketError);
	g_hSocket.Connect(OnSocketConnect, OnSocketReceive, OnSocketDisconnected, ServerIp, ServerPort);
}

public void OnSocketConnect(Handle socket, any arg) {
	char rcon_password[256];
	FindConVar("rcon_password").GetString(rcon_password, sizeof(rcon_password));
	if (rcon_password[0] == '\0') {
		SetFailState("You need to enable RCON to use this plugin");
	}
	// Escape out any percent symbols that should happen to be in the password
	ReplaceString(rcon_password, sizeof(rcon_password), "%", "%%");
	Send(SERVERDATA_AUTH, rcon_password);
}

public void OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile) {
	int i;
	while (i < dataSize) {
		int packetlen = ReadByte(receiveData[i]);
		int requestid = ReadByte(receiveData[i+4]);
		int serverdata = ReadByte(receiveData[i+8]);

		if (serverdata == 2) {
			if (requestid == 1) {
				Send(SERVERDATA_EXECCOMMAND, g_sCommand);
			}
			else {
				IRC_ReplyToCommand(g_sReplyNick, "Unable to connect to RCON");
			}
		}

		if (serverdata == 0 && requestid > 1) {
			char lines[64][256];
			int linecount = ExplodeString(receiveData[i+12], "\n", lines, sizeof(lines), sizeof(lines[]));
			for (int l; l < linecount; l++) {
				IRC_ReplyToCommand(g_sReplyNick, "%s", lines[l]);
			}
			g_bBusy = false;
			g_hSocket.Disconnect();
			g_iRequestId = 0;
			delete socket;
		}

		i += packetlen+4;
	}
}

public void OnSocketDisconnected(Handle socket, any hFile) {
	g_iRequestId = 0;
	delete socket;
}

public void OnSocketError(Handle socket, const int errorType, const int errorNum, any hFile) {
	LogError("socket error %d (errno %d)", errorType, errorNum);
	delete socket;
}

int ReadByte(const char[] recieveData) {
	int numbers[4];
	int number;

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
	g_iRequestId++;
	char packet[2048];
	char command[2048];

	VFormat(command, sizeof(command), format, 2);
	int num = strlen(command)+10;
	FormatEx(
		packet,
		sizeof(packet),
		"%c%c%c%c%c%c%c%c%c%c%c%c%s\x00\x00",
		num&0xFF,
		num >> 8&0xFF,
		num >> 16&0xFF,
		num >> 24&0xFF,
		g_iRequestId&0xFF,
		g_iRequestId >> 8&0xFF,
		g_iRequestId >> 16&0xFF,
		g_iRequestId >> 24&0xFF,
		type&0xFF,
		type >> 8&0xFF,
		type >> 16&0xFF,
		type >> 24&0xFF,
		command
	);
	
	g_hSocket.Send(packet, strlen(command)+14);
}

public void OnPluginEnd() {
	if (g_bIRC) {
		IRC_CleanUp();
	}
}

// http://bit.ly/defcon
