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

#pragma semicolon 1
#pragma newdecls required
#include <socket>
#include <sourceirc>

Socket
	// Global socket handle for the IRC connection
	  g_hSocket;
Handle
	// Queue for rate limiting	
	  g_hMessageTimer;
KeyValues
	// Global keyvalues handle for the config file
	  g_kvConfig;
ArrayList
	// Command registry for plugins using IRC_Reg*Cmd
	  g_aCommandPlugins
	, g_aCommands
	, g_aCommandCallbacks
	, g_aCommandDescriptions
	, g_aCommandFlags
	, g_aCommandPermissions
	// Event registry for plugins using IRC_HookEvent
	, g_aEventPlugins
	, g_aEvents
	, g_aEventCallbacks
	// Queue for rate limiting
	, g_aMessageQueue
	// Temporary storage for command and event arguments
	, g_aCmdArgs;
float
	  g_fMessageRate;
char
	// Temporary storage for command and event arguments
	  g_sCmdArgString[IRC_MAXLEN]
	, g_sCmdHostMask[IRC_MAXLEN]
	// My nickname
	, g_sNick[IRC_NICK_MAXLEN]
	// IRC can break messages into more than one packet, so this is temporary storage for "Broken" packets
	, g_sBrokenLine[IRC_MAXLEN];
bool
	// Are we connected yet?
	  g_bConnected;
int
	// Debug mode.
	  g_iDebug;

public Plugin myinfo = {
	name = "SourceIRC",
	author = "Azelphur",
	description = "An easy to use API to the IRC protocol",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
};

public void OnPluginStart() {
	CreateConVar("sourceirc_version", IRC_VERSION, "Current version of SourceIRC", FCVAR_REPLICATED|FCVAR_SPONLY|FCVAR_NOTIFY);
	LoadTranslations("sourceirc.phrases");

	g_aCommandPlugins = new ArrayList();
	g_aCommands = new ArrayList(IRC_CMD_MAXLEN);
	g_aCommandCallbacks = new ArrayList();
	g_aCommandDescriptions = new ArrayList(256);
	g_aCommandFlags = new ArrayList();
	g_aCommandPermissions = new ArrayList();

	g_aEventPlugins = new ArrayList();
	g_aEvents = new ArrayList(IRC_MAXLEN);
	g_aEventCallbacks = new ArrayList();

	g_aMessageQueue = new ArrayList(IRC_MAXLEN);

	g_aCmdArgs = new ArrayList(IRC_MAXLEN);

	g_bConnected = false;
	RegAdminCmd("irc_send", Command_Send, ADMFLAG_RCON, "irc_send <message>");
}

public void OnAllPluginsLoaded() {
	IRC_RegCmd("help", Command_Help, "help - Shows a list of g_aCommands available to you");
	IRC_HookEvent("433", Event_RAW433);
	IRC_HookEvent("NICK", Event_NICK);
}

public Action Event_RAW433(const char[] hostmask, int args) {
	if (!g_bConnected) {
		char nick[IRC_NICK_MAXLEN];
		IRC_GetNick(nick, sizeof(nick));
		LogError("Nickname %s is already in use, trying %s_", nick, nick);
		StrCat(nick, sizeof(nick), "_");
		IRC_Send("NICK %s", nick);
		strcopy(g_sNick, sizeof(g_sNick), nick);
	}
}

public Action Event_NICK(const char[] hostmask, int args) {
	char newnick[64];
	char oldnick[IRC_NICK_MAXLEN];

	IRC_GetNickFromHostMask(hostmask, oldnick, sizeof(oldnick));
	if (StrEqual(oldnick, g_sNick)) {
		IRC_GetEventArg(1, newnick, sizeof(newnick));
		strcopy(g_sNick, sizeof(g_sNick), newnick);
	}
}

public Action Command_Help(const char[] nick, int args) {
	char description[256];
	char hostmask[IRC_MAXLEN];

	IRC_GetHostMask(hostmask, sizeof(hostmask));
	for (int i = 0; i < g_aCommands.Length; i++) {
		if (IRC_GetAdminFlag(hostmask, g_aCommandPermissions.Get(i))) {
			g_aCommandDescriptions.GetString(i, description, sizeof(description));
			IRC_ReplyToCommand(nick, "%s", description);
		}
	}
	return Plugin_Handled;
}

public Action Command_Send(int client, int args) {
	if (g_bConnected) {
		char buffer[IRC_MAXLEN];
		GetCmdArgString(buffer, sizeof(buffer));
		IRC_Send(buffer);
	}
	else {
		ReplyToCommand(client, "%t", "Not Connected");
	}
}

public void OnConfigsExecuted() {
	if (g_hSocket == null) {
		LoadConfigs();
		Connect();
	}
}

void LoadConfigs() {
	g_kvConfig = new KeyValues("SourceIRC");
	char file[512];
	BuildPath(Path_SM, file, sizeof(file), "configs/sourceirc.cfg");
	g_kvConfig.ImportFromFile(file);
	g_kvConfig.JumpToKey("Settings");
	g_fMessageRate = g_kvConfig.GetFloat("msg-rate", 2.0);
	g_iDebug = g_kvConfig.GetNum("debug", 0);
	g_kvConfig.Rewind();
}

void Connect() {
	char server[256];
	g_kvConfig.JumpToKey("Server");
	g_kvConfig.GetString("server", server, sizeof(server), "");
	if (server[0] == '\0') {
		SetFailState("No server defined in sourceirc.cfg");
	}
	int port = g_kvConfig.GetNum("port", 6667);
	g_kvConfig.Rewind();
	g_hSocket = new Socket(SOCKET_TCP, OnSocketError);
	g_hSocket.Connect(OnSocketConnected, OnSocketReceive, OnSocketDisconnected, server, port);
}

public void OnSocketConnected(Handle socket, any arg) {
	char hostname[256];
	char realname[64];
	char ServerIp[16];
	char password[IRC_CHANNEL_MAXLEN];

	g_kvConfig.JumpToKey("Server");
	g_kvConfig.GetString("nickname", g_sNick, sizeof(g_sNick), "SourceIRC");
	g_kvConfig.GetString("realname", realname, sizeof(realname), "SourceIRC - http://Azelphur.com/project/sourceirc");
	g_kvConfig.GetString("password", password, sizeof(password), "");
	g_kvConfig.Rewind();
	SocketGetHostName(hostname, sizeof(hostname));

	int iIp = FindConVar("hostip").IntValue;
	Format(ServerIp, sizeof(ServerIp), "%i.%i.%i.%i", (iIp >> 24) & 0x000000FF,
                                                      (iIp >> 16) & 0x000000FF,
                                                      (iIp >>  8) & 0x000000FF,
                                                      (iIp >>  0) & 0x000000FF
    );

	if (password[0] != '\0') {
		IRC_Send("PASS %s", password);
	}
	IRC_Send("NICK %s", g_sNick);
	IRC_Send("USER %s %s %s :%s", g_sNick, hostname, ServerIp, realname);
}

public void OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile) {
	int startpos;
	char line[IRC_MAXLEN];
	char prefix[IRC_MAXLEN];
	char trailing[IRC_MAXLEN];

	static ArrayList args;
	if (args == null) {
		args = new ArrayList(IRC_MAXLEN);
	}

	while (startpos < dataSize) {
		startpos += SplitString(receiveData[startpos], "\n", line, sizeof(line));
		// is this the first part of a "Broken" packet?
		if (receiveData[startpos-1] != '\n') {
			strcopy(g_sBrokenLine, sizeof(g_sBrokenLine), line);
			break;
		}
		// Is this the latter half of a "Broken" packet? Stick it back together again.
		if (g_sBrokenLine[0] != '\0') {
			char originalline[IRC_MAXLEN];
			strcopy(originalline, sizeof(originalline), line);
			strcopy(line, sizeof(line), g_sBrokenLine);
			StrCat(line, sizeof(line), originalline);
			g_sBrokenLine[0] = '\x00';
		}
		if (line[strlen(line)-1] == '\r') {
			line[strlen(line)-1] = '\x00';
		}
		prefix[0] = '\x00';
		if (g_iDebug) {
			LogMessage("RECV %s", line);
		}
		if (line[0] == ':') {
			Split(line[1], " ", prefix, sizeof(prefix), line, sizeof(line));
		}
		if (StrContains(line, " :") != -1) {
			Split(line, " :", line, sizeof(line), trailing, sizeof(trailing));
			ExplodeString_Array(line, " ", args, IRC_MAXLEN);
			args.PushString(trailing);
		}
		else {
			ExplodeString_Array(line, " ", args, IRC_MAXLEN);
		}
		// packet has been parsed, time to send it off to HandleLine.
		HandleLine(prefix, args);
		args.Clear();
	}
}

void Split(const char[] source, const char[] split, char[] dest1_, int dest1maxlen, char[] dest2_, int dest2maxlen) {
	char[] dest1 = new char[dest1maxlen];
	char[] dest2 = new char[dest2maxlen];
	bool beforesplit = true;
	int strpos = 0;
	for (int i = 0; i <= strlen(source); i++) {
		if (beforesplit == true) {
			if (!strncmp(source[i], split, strlen(split))) {
				strpos = 0;
				dest1[i] = '\x00';
				beforesplit = false;
				i += strlen(split);
			}
		}
		if (beforesplit && strpos < dest1maxlen) {
			dest1[strpos] = source[i];
		}
		if (!beforesplit && strpos < dest2maxlen) {
			dest2[strpos] = source[i];
		}
		strpos++;
	}
	dest2[strpos] = '\x00';
	strcopy(dest1_, dest1maxlen, dest1);
	strcopy(dest2_, dest2maxlen, dest2);
}

void HandleLine(char[] prefix, ArrayList args) {
	char command[IRC_MAXLEN];
	char ev[IRC_MAXLEN];

	args.GetString(0, command, sizeof(command));
	// Is it a privmsg? check if it's a command and then run the command.
	if (StrEqual(command, "PRIVMSG")) {
		char message[IRC_MAXLEN];
		char channel[IRC_CHANNEL_MAXLEN];

		args.GetString(1, channel, sizeof(channel));
		args.GetString(2, message, sizeof(message));
		// CTCP Handling
		if ((message[0] == '\x01') && (message[strlen(message)-1] == '\x01')) {
			message[strlen(message)-1] = '\x00';
			char nick[IRC_NICK_MAXLEN];
			IRC_GetNickFromHostMask(prefix, nick, sizeof(nick));
			if (StrEqual(message[1], "VERSION", false)) {
				IRC_Send("NOTICE %s :\x01VERSION SourceIRC v%s - IRC Relay for source engine servers. http://azelphur.com/project/sourceirc\x01", nick, IRC_VERSION);
			}
			if (StrEqual(message[1], "PING", false)) {
				IRC_Send("NOTICE %s :\x01PONG\x01", nick);
			}
			return;
		}
		int argpos = IsTrigger(channel, message);
		if (argpos != -1) {
			RunCommand(prefix, message[argpos]);
			return;
		}
	}
	// Reply to PING
	else if (StrEqual(command, "PING", false)) {
		char reply[IRC_MAXLEN];
		args.GetString(1, reply, sizeof(reply));
		IRC_Send("PONG %s", reply);
	}
	// Recieved RAW 004 or RAW 376? We're connected. Yay!
	else if (!g_bConnected & (StrEqual(command, "004") || StrEqual(command, "376"))) {
		g_bConnected = true;
		ServerCommand("exec sourcemod/irc-connected.cfg");
		Handle connected = CreateGlobalForward("IRC_Connected", ET_Ignore);
		Call_StartForward(connected);
		Call_Finish();
		delete connected;
	}
	// Push g_aEvents to plugins that have hooked them.
	for (int i = 0; i < g_aEvents.Length; i++) {
		g_aEvents.GetString(i, ev, sizeof(ev));
		if (StrEqual(command, ev, false)) {
			Action result;
			g_aCmdArgs = args;
			Handle f = CreateForward(ET_Event, Param_String, Param_Cell);
			AddToForward(f, g_aEventPlugins.Get(i), g_aEventCallbacks.Get(i));
			Call_StartForward(f);
			Call_PushString(prefix);
			Call_PushCell(g_aCmdArgs.Length-1);
			Call_Finish(view_as<int>(result));
			delete f;
			if (result == Plugin_Stop) {
				return;
			}
		}
	}
	g_aCmdArgs.Clear();
}

int IsTrigger(const char[] channel, const char[] message) {
	char arg1[IRC_MAXLEN];
	char cmd_prefix[64];

	if (!g_kvConfig.JumpToKey("Server") || !g_kvConfig.JumpToKey("channels") || !g_kvConfig.JumpToKey(channel)) {
		cmd_prefix[0] = '\x00';
	}
	else {
		g_kvConfig.GetString("cmd_prefix", cmd_prefix, sizeof(cmd_prefix), "");
	}
	g_kvConfig.Rewind();
	for (int i = 0; i <= strlen(message); i++) {
		if (message[i] == ' ') {
			arg1[i] = '\x00';
			break;
		}
		arg1[i] = message[i];
	}
	int startpos = -1;
	if (StrEqual(channel, g_sNick, false)) {
		startpos = 0;
	}
	if (!strncmp(arg1, g_sNick, strlen(g_sNick), false) && !(strlen(arg1)-strlen(g_sNick) > 1)) {
		startpos = strlen(arg1);
	}
	else if (!StrEqual(cmd_prefix, "") && !strncmp(arg1, cmd_prefix, strlen(cmd_prefix))) {
		startpos = strlen(cmd_prefix);
	}
	else {
		char cmd[IRC_CMD_MAXLEN];
		for (int i = 0; i < g_aCommandFlags.Length; i++) {
			if (g_aCommandFlags.Get(i) == IRC_CMDFLAG_NOPREFIX) {
				g_aCommands.GetString(i, cmd, sizeof(cmd));
				if (!strncmp(arg1, cmd, strlen(cmd), false)) {
					startpos = 0;
					break;
				}
			}
		}
	}
	if (startpos != -1) {
		for (int i = startpos; i <= strlen(message); i++) {
			if (message[i] != ' ') {
				break;
			}
			startpos++;
		}
	}
	return startpos;
}

void RunCommand(const char[] hostmask, const char[] message) {
	char command[IRC_CMD_MAXLEN];
	char savedcommand[IRC_CMD_MAXLEN];
	char arg[IRC_MAXLEN];
	int newpos;
	int pos = BreakString(message, command, sizeof(command));

	if (pos == -1) {
		pos = 0;
	}
	strcopy(g_sCmdArgString, sizeof(g_sCmdArgString), message[pos]);
	strcopy(g_sCmdHostMask, sizeof(g_sCmdHostMask), hostmask);
	while (pos != -1) {
		pos = BreakString(message[newpos], arg, sizeof(arg));
		newpos += pos;
		g_aCmdArgs.PushString(arg);
	}
	char nick[IRC_NICK_MAXLEN];
	IRC_GetNickFromHostMask(hostmask, nick, sizeof(nick));
	int arraysize = g_aCommands.Length;
	bool IsPlugin_Handled;
	for (int i = 0; i < arraysize; i++) {
		g_aCommands.GetString(i, savedcommand, sizeof(savedcommand));
		if (StrEqual(command, savedcommand, false)) {
			if (IRC_GetAdminFlag(hostmask, g_aCommandPermissions.Get(i))) {
				Action result;
				Handle f = CreateForward(ET_Event, Param_String, Param_Cell);
				AddToForward(f, g_aCommandPlugins.Get(i), g_aCommandCallbacks.Get(i));
				Call_StartForward(f);
				Call_PushString(nick);
				Call_PushCell(g_aCmdArgs.Length-1);
				Call_Finish(view_as<int>(result));
				delete f;
				g_aCmdArgs.Clear();
				if (result == Plugin_Handled) {
					IsPlugin_Handled = true;
				}
				if (result == Plugin_Stop) {
					return;
				}
			}
			else {
				IRC_ReplyToCommand(nick, "%t", "Access Denied", command);
				return;
			}
		}
	}
	if (!IsPlugin_Handled) {
		IRC_ReplyToCommand(nick, "%t", "Unknown Command", command);
	}
}

public void IRC_Connected() {
	if (!g_kvConfig.JumpToKey("Server") || !g_kvConfig.JumpToKey("channels") || !g_kvConfig.GotoFirstSubKey()) {
		LogError("No channels defined in sourceirc.cfg");
	}
	else {
		char channel[IRC_CHANNEL_MAXLEN];
		char password[IRC_CHANNEL_MAXLEN];

		do {
			g_kvConfig.GetSectionName(channel, sizeof(channel));
			g_kvConfig.GetString("password", password, sizeof(password), "");
			if (password[0] == '\0') {
				IRC_Send("JOIN %s", channel);
			}
			else {
				IRC_Send("JOIN %s %s", channel, password);
			}
		}
		while (g_kvConfig.GotoNextKey());
	}
	g_kvConfig.Rewind();
}

public void OnSocketDisconnected(Handle socket, any hFile) {
	g_bConnected = false;
	CreateTimer(5.0, ReConnect);
	delete socket;
}

public Action ReConnect(Handle timer) {
	Connect();
}

public void OnSocketError(Handle socket, const int errorType, const int errorNum, any hFile) {
	g_bConnected = false;
	CreateTimer(5.0, ReConnect);
	LogError("socket error %d (errno %d)", errorType, errorNum);
	delete socket;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("sourceirc");
	// Create all the magical natives
	CreateNative("IRC_RegCmd", N_IRC_RegCmd);
	CreateNative("IRC_RegAdminCmd", N_IRC_RegAdminCmd);
	CreateNative("IRC_ReplyToCommand", N_IRC_ReplyToCommand);
	CreateNative("IRC_GetCmdArgString", N_IRC_GetCmdArgString);
	CreateNative("IRC_GetCmdArg", N_IRC_GetCmdArg);
	// Not a mistake, they both do the same thing for now.
	CreateNative("IRC_GetEventArg", N_IRC_GetCmdArg);

	CreateNative("IRC_GetServerDomain", N_IRC_GetServerDomain);
	CreateNative("IRC_HookEvent", N_IRC_HookEvent);
	CreateNative("IRC_GetTeamColor", N_IRC_GetTeamColor);

	CreateNative("IRC_GetHostMask", N_IRC_GetHostMask);
	CreateNative("IRC_CleanUp", N_IRC_CleanUp);
	CreateNative("IRC_ChannelHasFlag", N_IRC_ChannelHasFlag);
	CreateNative("IRC_Send", N_IRC_Send);
	CreateNative("IRC_GetUserFlagBits", N_IRC_GetUserFlagBits);
	CreateNative("IRC_GetAdminFlag", N_IRC_GetAdminFlag);
	CreateNative("IRC_MsgFlaggedChannels", N_IRC_MsgFlaggedChannels);
	CreateNative("IRC_GetCommandArrays", N_IRC_GetCommandArrays);
	CreateNative("IRC_GetNick", N_IRC_GetNick);
	return APLRes_Success;
}

public int N_IRC_GetServerDomain(Handle plugin, int numParams) {
	char AutoIP[32];
	char ServerDomain[128];

	int iIp = FindConVar("hostip").IntValue;
	Format(AutoIP, sizeof(AutoIP), "%i.%i.%i.%i:%d", (iIp >> 24) & 0x000000FF,
													 (iIp >> 16) & 0x000000FF,
													 (iIp >>  8) & 0x000000FF,
													 (iIp      ) & 0x000000FF,
													  FindConVar("hostport").IntValue);
	if (!g_kvConfig.JumpToKey("Settings")) {
		SetNativeString(1, AutoIP, GetNativeCell(2));
		return;
	}
	g_kvConfig.GetString("server-domain", ServerDomain, sizeof(ServerDomain), "");
	if (StrEqual(ServerDomain, "")) {
		SetNativeString(1, AutoIP, GetNativeCell(2));
		return;
	}

	SetNativeString(1, ServerDomain, GetNativeCell(2));
	g_kvConfig.Rewind();
}

public int N_IRC_GetTeamColor(Handle plugin, int numParams) {
	int team = GetNativeCell(1);
	if (!g_kvConfig.JumpToKey("Settings")) {
		return -1;
	}
	char key[16];
	Format(key, sizeof(key), "teamcolor-%d", team);
	int color = g_kvConfig.GetNum(key, -1);
	g_kvConfig.Rewind();
	return color;
}

public int N_IRC_GetHostMask(Handle plugin, int numParams) {
	SetNativeString(1, g_sCmdHostMask, GetNativeCell(2));
	return strlen(g_sCmdHostMask);
}

public int N_IRC_GetCmdArgString(Handle plugin, int numParams) {
	SetNativeString(1, g_sCmdArgString, GetNativeCell(2));
	return strlen(g_sCmdArgString);
}

public int N_IRC_GetCmdArg(Handle plugin, int numParams) {
	char str[IRC_MAXLEN];
	g_aCmdArgs.GetString(GetNativeCell(1), str, sizeof(str));
	SetNativeString(2, str, GetNativeCell(3));
	return strlen(str);
}

public int N_IRC_ReplyToCommand(Handle plugin, int numParams) {
	char buffer[512];
	char nick[64];

	int written;

	GetNativeString(1, nick, sizeof(nick));
	FormatNativeString(0, 2, 3, sizeof(buffer), written, buffer);
	IRC_Send("NOTICE %s :%s", nick, buffer);
}

public int N_IRC_GetNick(Handle plugin, int numParams) {
	int maxlen = GetNativeCell(2);
	SetNativeString(1, g_sNick, maxlen);
}

public int N_IRC_GetCommandArrays(Handle plugin, int numParams) {
	ArrayList CommandsArg = GetNativeCell(1);
	ArrayList CommandPluginsArg = GetNativeCell(2);
	ArrayList CommandCallbacksArg = GetNativeCell(3);
	ArrayList CommandDescriptionsArg = GetNativeCell(4);

	char command[64];
	char description[256];

	for (int i = 0; i < g_aCommandPlugins.Length; i++) {
		g_aCommands.GetString(i, command, sizeof(command));
		g_aCommandDescriptions.GetString(i, description, sizeof(description));

		CommandsArg.PushString(command);
		CommandPluginsArg.Push(g_aCommandPlugins.Get(i));
		CommandCallbacksArg.Push(g_aCommandCallbacks.Get(i));
		CommandDescriptionsArg.PushString(description);
	}
}

public int N_IRC_HookEvent(Handle plugin, int numParams) {
	char ev[IRC_MAXLEN];
	GetNativeString(1, ev, sizeof(ev));

	g_aEventPlugins.Push(plugin);
	g_aEvents.PushString(ev);
	g_aEventCallbacks.Push(GetNativeCell(2));
}

public int N_IRC_RegCmd(Handle plugin, int numParams) {
	char command[IRC_CMD_MAXLEN];
	char description[256];

	GetNativeString(1, command, sizeof(command));
	GetNativeString(3, description, sizeof(description));
	g_aCommandPlugins.Push(plugin);
	g_aCommands.PushString(command);
	g_aCommandCallbacks.Push(GetNativeCell(2));
	g_aCommandPermissions.Push(0);
	g_aCommandFlags.Push(GetNativeCell(4));
	g_aCommandDescriptions.PushString(description);
}

public int N_IRC_RegAdminCmd(Handle plugin, int numParams) {
	char command[IRC_CMD_MAXLEN];
	char description[256];

	GetNativeString(1, command, sizeof(command));
	GetNativeString(4, description, sizeof(description));
	g_aCommandPlugins.Push(plugin);
	g_aCommands.PushString(command);
	g_aCommandCallbacks.Push(GetNativeCell(2));
	g_aCommandPermissions.Push(GetNativeCell(3));
	g_aCommandFlags.Push(GetNativeCell(5));
	g_aCommandDescriptions.PushString(description);
}

public int N_IRC_CleanUp(Handle plugin, int numParams) {
	for (int i = 0; i < g_aCommandPlugins.Length; i++) {
		if (plugin == g_aCommandPlugins.Get(i)) {
			g_aCommandPlugins.Erase(i);
			g_aCommands.Erase(i);
			g_aCommandCallbacks.Erase(i);
			g_aCommandPermissions.Erase(i);
			g_aCommandDescriptions.Erase(i);
			g_aCommandFlags.Erase(i);
			i--;
		}
	}
	for (int i = 0; i < g_aEventPlugins.Length; i++) {
		if (plugin == g_aEventPlugins.Get(i)) {
			g_aEventPlugins.Erase(i);
			g_aEvents.Erase(i);
			g_aEventCallbacks.Erase(i);
			i--;
		}
	}
}

public int N_IRC_ChannelHasFlag(Handle plugin, int numParams) {
	char flag[64];
	char channel[IRC_CHANNEL_MAXLEN];

	GetNativeString(1, channel, sizeof(channel));
	GetNativeString(2, flag, sizeof(flag));
	if (!g_kvConfig.JumpToKey("Server") || !g_kvConfig.JumpToKey("channels") || !g_kvConfig.JumpToKey(channel)) {
		g_kvConfig.Rewind();
		return 0;
	}
	int result = g_kvConfig.GetNum(flag, 0);
	g_kvConfig.Rewind();
	return result;
}

public int N_IRC_GetAdminFlag(Handle plugin, int numParams) {
	char hostmask[512];
	int flag = GetNativeCell(2);
	if (flag == 0) {
		return true;
	}
	GetNativeString(1, hostmask, sizeof(hostmask));
	int userflag = IRC_GetUserFlagBits(hostmask);
	if (userflag & ADMFLAG_ROOT || userflag & flag) {
		return true;
	}
	return false;
}

public int N_IRC_GetUserFlagBits(Handle plugin, int numParams) {
	char hostmask[512];
	GetNativeString(1, hostmask, sizeof(hostmask));
	int resultflag;
	Handle f = CreateGlobalForward("IRC_RetrieveUserFlagBits", ET_Ignore, Param_String, Param_CellByRef);
	Call_StartForward(f);
	Call_PushString(hostmask);
	Call_PushCellRef(resultflag);
	Call_Finish();
	delete f;
	return view_as<int>(resultflag);
}

public int N_IRC_Send(Handle plugin, int numParams) {
	char buffer[IRC_MAXLEN];
	int written;

	FormatNativeString(0, 1, 2, sizeof(buffer), written, buffer);
	if (StrContains(buffer, "\n") != -1 || StrContains(buffer, "\r") != -1) {
		ThrowNativeError(1, "String contains \n or \r");
		return;
	}

	if ((g_bConnected) && (g_fMessageRate != 0.0)) {
		if (g_hMessageTimer != null) {
			g_aMessageQueue.PushString(buffer);
			return;
		}
		g_hMessageTimer = CreateTimer(g_fMessageRate, MessageTimerCB);
	}
	Format(buffer, sizeof(buffer), "%s\r\n", buffer);
	if (g_iDebug) {
		LogMessage("SEND %s", buffer);
	}
	
	g_hSocket.Send(buffer);
}

public Action MessageTimerCB(Handle timer) {
	g_hMessageTimer = null;
	char buffer[IRC_MAXLEN];
	if (g_aMessageQueue.Length > 0) {
		g_aMessageQueue.GetString(0, buffer, sizeof(buffer));
		IRC_Send(buffer);
		g_aMessageQueue.Erase(0);
	}
}

public int N_IRC_MsgFlaggedChannels(Handle plugin, int numParams) {
	if (!g_bConnected) {
		return 0;
	}
	char flag[64];
	char text[IRC_MAXLEN];
	int written;

	GetNativeString(1, flag, sizeof(flag));
	FormatNativeString(0, 2, 3, sizeof(text), written, text);
	if (!g_kvConfig.JumpToKey("Server") || !g_kvConfig.JumpToKey("channels") || !g_kvConfig.GotoFirstSubKey()) {
		LogError("No channels defined in sourceirc.cfg");
	}
	else {
		char channel[IRC_CHANNEL_MAXLEN];
		do {
			g_kvConfig.GetSectionName(channel, sizeof(channel));
			if (g_kvConfig.GetNum(flag, 0)) {
				IRC_Send("PRIVMSG %s :%s", channel, text);
			}
		}
		while (g_kvConfig.GotoNextKey());
	}
	g_kvConfig.Rewind();
	return 1;
}

// http://bit.ly/defco$