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

// Global socket handle for the IRC connection
Handle
	gsocket;
// Global keyvalues handle for the config file
KeyValues
	kv;
ArrayList
	// Command registry for plugins using IRC_Reg*Cmd
	CommandPlugins
	, Commands
	, CommandCallbacks
	, CommandDescriptions
	, CommandFlags
	, CommandPermissions
	// Event registry for plugins using IRC_HookEvent
	, EventPlugins
	, Events
	, EventCallbacks
	// Queue for rate limiting
	, messagequeue
	// Temporary storage for command and event arguments
	, cmdargs;
// Queue for rate limiting	
Handle
	messagetimer;
float
	messagerate;
// Temporary storage for command and event arguments
char
	cmdargstring[IRC_MAXLEN]
	, cmdhostmask[IRC_MAXLEN]
	// My nickname
	, g_nick[IRC_NICK_MAXLEN]
	// IRC can break messages into more than one packet, so this is temporary storage for "Broken" packets
	, brokenline[IRC_MAXLEN];
// Are we connected yet?
bool
	g_connected;
// Debug mode.
int
	g_debug;

public Plugin myinfo = {
	name = "SourceIRC",
	author = "Azelphur",
	description = "An easy to use API to the IRC protocol",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
};

public void OnPluginStart() {
	RegPluginLibrary("sourceirc");

	CreateConVar("sourceirc_version", IRC_VERSION, "Current version of SourceIRC", FCVAR_REPLICATED|FCVAR_SPONLY|FCVAR_NOTIFY);
	LoadTranslations("sourceirc.phrases");

	CommandPlugins = new ArrayList();
	Commands = new ArrayList(IRC_CMD_MAXLEN);
	CommandCallbacks = new ArrayList();
	CommandDescriptions = new ArrayList(256);
	CommandFlags = new ArrayList();
	CommandPermissions = new ArrayList();

	EventPlugins = new ArrayList();
	Events = new ArrayList(IRC_MAXLEN);
	EventCallbacks = new ArrayList();

	messagequeue = new ArrayList(IRC_MAXLEN);

	cmdargs = new ArrayList(IRC_MAXLEN);

	g_connected = false;
	RegAdminCmd("irc_send", Command_Send, ADMFLAG_RCON, "irc_send <message>");
}

public void OnAllPluginsLoaded() {
	IRC_RegCmd("help", Command_Help, "help - Shows a list of commands available to you");
	IRC_HookEvent("433", Event_RAW433);
	IRC_HookEvent("NICK", Event_NICK);
}

public Action Event_RAW433(const char[] hostmask, int args) {
	if (!g_connected) {
		char nick[IRC_NICK_MAXLEN];
		IRC_GetNick(nick, sizeof(nick));
		LogError("Nickname %s is already in use, trying %s_", nick, nick);
		StrCat(nick, sizeof(nick), "_");
		IRC_Send("NICK %s", nick);
		strcopy(g_nick, sizeof(g_nick), nick);
	}
}

public Action Event_NICK(const char[] hostmask, int args) {
	char
		newnick[64]
		, oldnick[IRC_NICK_MAXLEN];

	IRC_GetNickFromHostMask(hostmask, oldnick, sizeof(oldnick));
	if (StrEqual(oldnick, g_nick)) {
		IRC_GetEventArg(1, newnick, sizeof(newnick));
		strcopy(g_nick, sizeof(g_nick), newnick);
	}
}

public Action Command_Help(const char[] nick, int args) {
	char
		description[256]
		, hostmask[IRC_MAXLEN];

	IRC_GetHostMask(hostmask, sizeof(hostmask));
	for (int i = 0; i < Commands.Length; i++) {
		if (IRC_GetAdminFlag(hostmask, CommandPermissions.Get(i))) {
			CommandDescriptions.GetString(i, description, sizeof(description));
			IRC_ReplyToCommand(nick, "%s", description);
		}
	}
	return Plugin_Handled;
}

public Action Command_Send(int client, int args) {
	if (g_connected) {
		char buffer[IRC_MAXLEN];
		GetCmdArgString(buffer, sizeof(buffer));
		IRC_Send(buffer);
	}
	else {
		ReplyToCommand(client, "%t", "Not Connected");
	}
}

public void OnConfigsExecuted() {
	if (gsocket == null) {
		LoadConfigs();
		Connect();
	}
}

void LoadConfigs() {
	kv = new KeyValues("SourceIRC");
	char file[512];
	BuildPath(Path_SM, file, sizeof(file), "configs/sourceirc.cfg");
	kv.ImportFromFile(file);
	kv.JumpToKey("Settings");
	messagerate = kv.GetFloat("msg-rate", 2.0);
	g_debug = kv.GetNum("debug", 0);
	kv.Rewind();
}

void Connect() {
	char server[256];
	kv.JumpToKey("Server");
	kv.GetString("server", server, sizeof(server), "");
	if (StrEqual(server, "")) {
		SetFailState("No server defined in sourceirc.cfg");
	}
	int port = kv.GetNum("port", 6667);
	kv.Rewind();
	gsocket = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketConnect(gsocket, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, server, port);
}

public void OnSocketConnected(Handle socket, any arg) {
	char
		hostname[256]
		, realname[64]
		, ServerIp[16]
		, password[IRC_CHANNEL_MAXLEN];

	kv.JumpToKey("Server");
	kv.GetString("nickname", g_nick, sizeof(g_nick), "SourceIRC");
	kv.GetString("realname", realname, sizeof(realname), "SourceIRC - http://Azelphur.com/project/sourceirc");
	kv.GetString("password", password, sizeof(password), "");
	kv.Rewind();
	SocketGetHostName(hostname, sizeof(hostname));

	int iIp = FindConVar("hostip").IntValue;
	Format(ServerIp, sizeof(ServerIp), "%i.%i.%i.%i", (iIp >> 24) & 0x000000FF,
                                                      (iIp >> 16) & 0x000000FF,
                                                      (iIp >>  8) & 0x000000FF,
                                                      (iIp >>  0) & 0x000000FF);

	if (!StrEqual(password, "")) {
		IRC_Send("PASS %s", password);
	}
	IRC_Send("NICK %s", g_nick);
	IRC_Send("USER %s %s %s :%s", g_nick, hostname, ServerIp, realname);
}

public void OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile) {
	int
		startpos;
	char
		line[IRC_MAXLEN]
		, prefix[IRC_MAXLEN]
		, trailing[IRC_MAXLEN];

	static ArrayList args;
	if (args == null) {
		args = new ArrayList(IRC_MAXLEN);
	}

	while (startpos < dataSize) {
		startpos += SplitString(receiveData[startpos], "\n", line, sizeof(line));
		// is this the first part of a "Broken" packet?
		if (receiveData[startpos-1] != '\n') {
			strcopy(brokenline, sizeof(brokenline), line);
			break;
		}
		// Is this the latter half of a "Broken" packet? Stick it back together again.
		if (!StrEqual(brokenline, "")) {
			char originalline[IRC_MAXLEN];
			strcopy(originalline, sizeof(originalline), line);
			strcopy(line, sizeof(line), brokenline);
			StrCat(line, sizeof(line), originalline);
			brokenline[0] = '\x00';
		}
		if (line[strlen(line)-1] == '\r') {
			line[strlen(line)-1] = '\x00';
		}
		prefix[0] = '\x00';
		if (g_debug) {
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
	char
		command[IRC_MAXLEN]
		, ev[IRC_MAXLEN];

	args.GetString(0, command, sizeof(command));
	// Is it a privmsg? check if it's a command and then run the command.
	if (StrEqual(command, "PRIVMSG")) {
		char
			message[IRC_MAXLEN]
			, channel[IRC_CHANNEL_MAXLEN];

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
	else if (!g_connected & (StrEqual(command, "004") || StrEqual(command, "376"))) {
		g_connected = true;
		ServerCommand("exec sourcemod/irc-connected.cfg");
		Handle connected = CreateGlobalForward("IRC_Connected", ET_Ignore);
		Call_StartForward(connected);
		Call_Finish();
		delete connected;
	}
	// Push events to plugins that have hooked them.
	for (int i = 0; i < Events.Length; i++) {
		Events.GetString(i, ev, sizeof(ev));
		if (StrEqual(command, ev, false)) {
			Action result;
			cmdargs = args;
			Handle f = CreateForward(ET_Event, Param_String, Param_Cell);
			AddToForward(f, EventPlugins.Get(i), EventCallbacks.Get(i));
			Call_StartForward(f);
			Call_PushString(prefix);
			Call_PushCell(cmdargs.Length-1);
			Call_Finish(view_as<int>(result));
			delete f;
			if (result == Plugin_Stop) {
				return;
			}
		}
	}
	cmdargs.Clear();
}

int IsTrigger(const char[] channel, const char[] message) {
	char
		arg1[IRC_MAXLEN]
		, cmd_prefix[64];

	if (!kv.JumpToKey("Server") || !kv.JumpToKey("channels") || !kv.JumpToKey(channel)) {
		cmd_prefix[0] = '\x00';
	}
	else {
		kv.GetString("cmd_prefix", cmd_prefix, sizeof(cmd_prefix), "");
	}
	kv.Rewind();
	for (int i = 0; i <= strlen(message); i++) {
		if (message[i] == ' ') {
			arg1[i] = '\x00';
			break;
		}
		arg1[i] = message[i];
	}
	int startpos = -1;
	if (StrEqual(channel, g_nick, false)) {
		startpos = 0;
	}
	if (!strncmp(arg1, g_nick, strlen(g_nick), false) && !(strlen(arg1)-strlen(g_nick) > 1)) {
		startpos = strlen(arg1);
	}
	else if (!StrEqual(cmd_prefix, "") && !strncmp(arg1, cmd_prefix, strlen(cmd_prefix))) {
		startpos = strlen(cmd_prefix);
	}
	else {
		char cmd[IRC_CMD_MAXLEN];
		for (int i = 0; i < CommandFlags.Length; i++) {
			if (CommandFlags.Get(i) == IRC_CMDFLAG_NOPREFIX) {
				Commands.GetString(i, cmd, sizeof(cmd));
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
	char
		command[IRC_CMD_MAXLEN]
		, savedcommand[IRC_CMD_MAXLEN]
		, arg[IRC_MAXLEN];
	int
		newpos
		, pos = BreakString(message, command, sizeof(command));

	if (pos == -1) {
		pos = 0;
	}
	strcopy(cmdargstring, sizeof(cmdargstring), message[pos]);
	strcopy(cmdhostmask, sizeof(cmdhostmask), hostmask);
	while (pos != -1) {
		pos = BreakString(message[newpos], arg, sizeof(arg));
		newpos += pos;
		cmdargs.PushString(arg);
	}
	char nick[IRC_NICK_MAXLEN];
	IRC_GetNickFromHostMask(hostmask, nick, sizeof(nick));
	int arraysize = Commands.Length;
	bool IsPlugin_Handled;
	for (int i = 0; i < arraysize; i++) {
		Commands.GetString(i, savedcommand, sizeof(savedcommand));
		if (StrEqual(command, savedcommand, false)) {
			if (IRC_GetAdminFlag(hostmask, CommandPermissions.Get(i))) {
				Action result;
				Handle f = CreateForward(ET_Event, Param_String, Param_Cell);
				AddToForward(f, CommandPlugins.Get(i), CommandCallbacks.Get(i));
				Call_StartForward(f);
				Call_PushString(nick);
				Call_PushCell(cmdargs.Length-1);
				Call_Finish(view_as<int>(result));
				delete f;
				cmdargs.Clear();
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
	if (!kv.JumpToKey("Server") || !kv.JumpToKey("channels") || !kv.GotoFirstSubKey()) {
		LogError("No channels defined in sourceirc.cfg");
	}
	else {
		char
			channel[IRC_CHANNEL_MAXLEN]
			, password[IRC_CHANNEL_MAXLEN];

		do {
			kv.GetSectionName(channel, sizeof(channel));
			kv.GetString("password", password, sizeof(password), "");
			if (StrEqual(password, "")) {
				IRC_Send("JOIN %s", channel);
			}
			else {
				IRC_Send("JOIN %s %s", channel, password);
			}
		}
		while (kv.GotoNextKey());
	}
	kv.Rewind();
}

public void OnSocketDisconnected(Handle socket, any hFile) {
	g_connected = false;
	CreateTimer(5.0, ReConnect);
	delete socket;
}

public Action ReConnect(Handle timer) {
	Connect();
}

public void OnSocketError(Handle socket, const int errorType, const int errorNum, any hFile) {
	g_connected = false;
	CreateTimer(5.0, ReConnect);
	LogError("socket error %d (errno %d)", errorType, errorNum);
	delete socket;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
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
	char
		AutoIP[32]
		, ServerDomain[128];

	int iIp = FindConVar("hostip").IntValue;
	Format(AutoIP, sizeof(AutoIP), "%i.%i.%i.%i:%d", (iIp >> 24) & 0x000000FF,
														  (iIp >> 16) & 0x000000FF,
														  (iIp >>  8) & 0x000000FF,
														  iIp         & 0x000000FF,
														  FindConVar("hostport").IntValue);
	if (!kv.JumpToKey("Settings")) {
		SetNativeString(1, AutoIP, GetNativeCell(2));
		return;
	}
	kv.GetString("server-domain", ServerDomain, sizeof(ServerDomain), "");
	if (StrEqual(ServerDomain, "")) {
		SetNativeString(1, AutoIP, GetNativeCell(2));
		return;
	}

	SetNativeString(1, ServerDomain, GetNativeCell(2));
	kv.Rewind();
}

public int N_IRC_GetTeamColor(Handle plugin, int numParams) {
	int team = GetNativeCell(1);
	if (!kv.JumpToKey("Settings")) {
		return -1;
	}
	char key[16];
	Format(key, sizeof(key), "teamcolor-%d", team);
	int color = kv.GetNum(key, -1);
	kv.Rewind();
	return color;
}

public int N_IRC_GetHostMask(Handle plugin, int numParams) {
	SetNativeString(1, cmdhostmask, GetNativeCell(2));
	return strlen(cmdhostmask);
}

public int N_IRC_GetCmdArgString(Handle plugin, int numParams) {
	SetNativeString(1, cmdargstring, GetNativeCell(2));
	return strlen(cmdargstring);
}

public int N_IRC_GetCmdArg(Handle plugin, int numParams) {
	char str[IRC_MAXLEN];
	cmdargs.GetString(GetNativeCell(1), str, sizeof(str));
	SetNativeString(2, str, GetNativeCell(3));
	return strlen(str);
}

public int N_IRC_ReplyToCommand(Handle plugin, int numParams) {
	char
		buffer[512]
		, nick[64];
	int
		written;

	GetNativeString(1, nick, sizeof(nick));
	FormatNativeString(0, 2, 3, sizeof(buffer), written, buffer);
	IRC_Send("NOTICE %s :%s", nick, buffer);
}

public int N_IRC_GetNick(Handle plugin, int numParams) {
	int maxlen = GetNativeCell(2);
	SetNativeString(1, g_nick, maxlen);
}

public int N_IRC_GetCommandArrays(Handle plugin, int numParams) {
	ArrayList
		CommandsArg = GetNativeCell(1)
		, CommandPluginsArg = GetNativeCell(2)
		, CommandCallbacksArg = GetNativeCell(3)
		, CommandDescriptionsArg = GetNativeCell(4);
	char
		command[64]
		, description[256];

	for (int i = 0; i < CommandPlugins.Length; i++) {
		Commands.GetString(i, command, sizeof(command));
		CommandDescriptions.GetString(i, description, sizeof(description));

		CommandsArg.PushString(command);
		CommandPluginsArg.Push(CommandPlugins.Get(i));
		CommandCallbacksArg.Push(CommandCallbacks.Get(i));
		CommandDescriptionsArg.PushString(description);
	}
}

public int N_IRC_HookEvent(Handle plugin, int numParams) {
	char ev[IRC_MAXLEN];
	GetNativeString(1, ev, sizeof(ev));

	EventPlugins.Push(plugin);
	Events.PushString(ev);
	EventCallbacks.Push(GetNativeCell(2));
}

public int N_IRC_RegCmd(Handle plugin, int numParams) {
	char
		command[IRC_CMD_MAXLEN]
		, description[256];
	GetNativeString(1, command, sizeof(command));
	GetNativeString(3, description, sizeof(description));
	CommandPlugins.Push(plugin);
	Commands.PushString(command);
	CommandCallbacks.Push(GetNativeCell(2));
	CommandPermissions.Push(0);
	CommandFlags.Push(GetNativeCell(4));
	CommandDescriptions.PushString(description);
}

public int N_IRC_RegAdminCmd(Handle plugin, int numParams) {
	char
		command[IRC_CMD_MAXLEN]
		, description[256];

	GetNativeString(1, command, sizeof(command));
	GetNativeString(4, description, sizeof(description));
	CommandPlugins.Push(plugin);
	Commands.PushString(command);
	CommandCallbacks.Push(GetNativeCell(2));
	CommandPermissions.Push(GetNativeCell(3));
	CommandFlags.Push(GetNativeCell(5));
	CommandDescriptions.PushString(description);
}

public int N_IRC_CleanUp(Handle plugin, int numParams) {
	for (int i = 0; i < CommandPlugins.Length; i++) {
		if (plugin == CommandPlugins.Get(i)) {
			CommandPlugins.Erase(i);
			Commands.Erase(i);
			CommandCallbacks.Erase(i);
			CommandPermissions.Erase(i);
			CommandDescriptions.Erase(i);
			CommandFlags.Erase(i);
			i--;
		}
	}
	for (int i = 0; i < EventPlugins.Length; i++) {
		if (plugin == EventPlugins.Get(i)) {
			EventPlugins.Erase(i);
			Events.Erase(i);
			EventCallbacks.Erase(i);
			i--;
		}
	}
}

public int N_IRC_ChannelHasFlag(Handle plugin, int numParams) {
	char
		flag[64]
		, channel[IRC_CHANNEL_MAXLEN];

	GetNativeString(1, channel, sizeof(channel));
	GetNativeString(2, flag, sizeof(flag));
	if (!kv.JumpToKey("Server") || !kv.JumpToKey("channels") || !kv.JumpToKey(channel)) {
		kv.Rewind();
		return 0;
	}
	int result = kv.GetNum(flag, 0);
	kv.Rewind();
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
	if (userflag & ADMFLAG_ROOT) {
		return true;
	}
	if (userflag & flag) {
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

	if ((g_connected) && (messagerate != 0.0)) {
		if (messagetimer != null) {
			messagequeue.PushString(buffer);
			return;
		}
		messagetimer = CreateTimer(messagerate, MessageTimerCB);
	}
	Format(buffer, sizeof(buffer), "%s\r\n", buffer);
	if (g_debug) {
		LogMessage("SEND %s", buffer);
	}
	SocketSend(gsocket, buffer);
}

public Action MessageTimerCB(Handle timer) {
	messagetimer = null;
	char buffer[IRC_MAXLEN];
	if (messagequeue.Length > 0) {
		messagequeue.GetString(0, buffer, sizeof(buffer));
		IRC_Send(buffer);
		messagequeue.Erase(0);
	}
}

public int N_IRC_MsgFlaggedChannels(Handle plugin, int numParams) {
	if (!g_connected) {
		return 0;
	}
	char
		flag[64]
		, text[IRC_MAXLEN];
	int
		written;

	GetNativeString(1, flag, sizeof(flag));
	FormatNativeString(0, 2, 3, sizeof(text), written, text);
	if (!kv.JumpToKey("Server") || !kv.JumpToKey("channels") || !kv.GotoFirstSubKey()) {
		LogError("No channels defined in sourceirc.cfg");
	}
	else {
		char channel[IRC_CHANNEL_MAXLEN];
		do {
			kv.GetSectionName(channel, sizeof(channel));
			if (kv.GetNum(flag, 0)) {
				IRC_Send("PRIVMSG %s :%s", channel, text);
			}
		}
		while (kv.GotoNextKey());
	}
	kv.Rewind();
	return 1;
}

// http://bit.ly/defco$
