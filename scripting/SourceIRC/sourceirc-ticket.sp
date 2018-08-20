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

#include <sdktools>
#undef REQUIRE_PLUGIN
#include <sourceirc>

float
	SprayLocation[MAXPLAYERS+1][3];
char
	ReportString[MAXPLAYERS+1][512];
KeyValues
	kv;

public Plugin myinfo = {
	name = "SourceIRC -> Ticket",
	author = "Azelphur",
	description = "Adds a report command in game for players to report problems to staff in an IRC channel",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
};

public void OnPluginStart() {
	char file[512];
	LoadTranslations("common.phrases");
	RegConsoleCmd("report", Command_Support);
	RegConsoleCmd("reply", Command_Reply);
	AddTempEntHook("Player Decal", PlayerSpray);
	kv = new KeyValues("SourceIRC");
	BuildPath(Path_SM, file, sizeof(file), "configs/sourceirc.cfg");
	kv.ImportFromFile(file);
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
	IRC_RegAdminCmd("to", Command_To, ADMFLAG_CHAT, "to <name|#userid> <text> - Send a message to a player");
}

public Action Command_Reply(int client, int args) {
	char
		Args[256]
		, name[64]
		, auth[64];

	GetCmdArgString(Args, sizeof(Args));
	if (StrEqual(Args, "")) {
		return Plugin_Handled;
	}
	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	IRC_MsgFlaggedChannels("ticket", "%s (%s) :  %s", name, auth, Args);
	PrintToChat(client, "To ADMIN :  %s", Args);
	return Plugin_Handled;
}

public Action Command_To(const char[] nick, int args) {
	char
		destination[64]
		, text[IRC_MAXLEN];
	
	IRC_GetCmdArgString(text, sizeof(text));
	int startpos = BreakString(text, destination, sizeof(destination));
	int target = FindTarget(0, destination, true, false);
	if (target != -1) {
		PrintToChat(target, "\x01[\x04IRC\x01] \x03(ADMIN) %s\x01 :  %s", nick, text[startpos]);
	}
	else {
		IRC_ReplyToCommand(nick, "Unable to find %s", destination);
	}
	return Plugin_Handled;
}

public Action PlayerSpray(const char[] te_name, const clients[], int client_count, float delay) {
	int client = TE_ReadNum("m_nPlayer");
	TE_ReadVector("m_vecOrigin", SprayLocation[client]);
}

int TraceSpray(int client) {
 	float pos[3];
	if (GetPlayerEye(client, pos) >= 1){
		float MaxDis = 50.0;
		for (int i = 1; i <= MAXPLAYERS; i++) {
			if (GetVectorDistance(pos, SprayLocation[i]) <= MaxDis) {
				return i;
			}
		}
	}
	return 0;
}

int GetPlayerEye(int client, float pos[3]) {
	float
		vAngles[3]
		, vOrigin[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);

	if (TR_DidHit(trace)) {
		TR_GetEndPosition(pos, trace);
		if (GetVectorDistance(pos, vOrigin) <= 128.0) {
			return 2;
		}
		return 1;
	}
	return 0;
}

bool TraceEntityFilterPlayer(int entity, int contentsMask) {
 	char classname[64];
 	GetEntityNetClass(entity, classname, 64);
 	return !StrEqual(classname, "CTFPlayer");
}

public Action Command_Support(int client, int args) {
	Menu hMenu = new Menu(MenuHandler_Report);
	hMenu.SetTitle("What do you want to report for?");
	if (!kv.JumpToKey("Ticket")) {
		return;
	}
	if (!kv.JumpToKey("Menu")) {
		return;
	}
	if (!kv.GotoFirstSubKey(false)) {
		return;
	}
	char
		key[64]
		, value[64];
	do {
		kv.GetSectionName(key, sizeof(key));
		kv.GetString(NULL_STRING, value, sizeof(value));
		hMenu.AddItem(key, value);
	} while (kv.GotoNextKey(false));

	kv.Rewind();

	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Report(Menu hMenu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		hMenu.GetItem(param2, ReportString[param1], sizeof(ReportString[]));
		if (StrEqual(ReportString[param1], "{Special:Spray}")) {
			SprayMenu(param1);
		}
		else {
			ShowPlayerList(param1);
		}
	}
}

void SprayMenu(int client) {
	Menu hMenu = new Menu(MenuHandler_SprayMenu);
	hMenu.SetTitle("Aim at the spray you wish to report, then press ok.");
	hMenu.AddItem("Ok", "Ok");
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SprayMenu(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
		Command_Support(param1, 0);
	}
	else if (action == MenuAction_Select) {
		int target = TraceSpray(param1);
		if (!target) {
			PrintToChat(param1, "No spray found where you are looking, try getting closer!");
			SprayMenu(param1);
		}
		else {
			char
				decalfile[256]
				, sprayurl[128];

			GetPlayerDecalFile(target, decalfile, sizeof(decalfile));
			sprayurl[0] = '\x00';
			Format(ReportString[param1], sizeof(ReportString[]), "Bad spray");
			if ((kv.JumpToKey("Ticket")) && (kv.JumpToKey("Settings"))) {
				kv.GetString("spray_url", sprayurl, sizeof(sprayurl), "");
				if (!StrEqual(sprayurl, "")) {
					ReplaceString(sprayurl, sizeof(sprayurl), "{SPRAY}", decalfile);
					StrCat(ReportString[param1], sizeof(ReportString), " ");
					StrCat(ReportString[param1], sizeof(ReportString), sprayurl);
				}
			}
			kv.Rewind();

			Report(param1, target, ReportString[param1]);
		}
	}
}

void ShowPlayerList(int client) {
	char
		title[256]
		, disp[64]
		, info[64];

	Format(title, sizeof(title), "Who do you want to report for %s", ReportString[client]);
	Menu hMenu = new Menu(MenuHandler_PlayerList);
	hMenu.SetTitle(title);
	hMenu.ExitBackButton = true;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientConnected(i) && !IsFakeClient(i)) {
			GetClientName(i, disp, sizeof(disp));
			IntToString(GetClientUserId(i), info, sizeof(info));
			hMenu.AddItem(info, disp);
		}
	}
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_PlayerList(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
		Command_Support(param1, 0);
	}
	else if (action == MenuAction_Select) {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int client = GetClientOfUserId(StringToInt(info));

		if (!client) {
			PrintToChat(param1, "Player disconnected, sorry!");
		}
		else {
			Report(param1, client, ReportString[param1]);
		}
	}
}

void Report(int client, int target, char[] info) {
	char
		name[64]
		, auth[64]
		, targetname[64]
		, targetauth[64]
		, mynick[64];

	GetClientName(client, name, sizeof(name));
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	GetClientName(target, targetname, sizeof(targetname));
	GetClientAuthId(target, AuthId_Steam2, targetauth, sizeof(targetauth));
	IRC_GetNick(mynick, sizeof(mynick));
	if ((kv.JumpToKey("Ticket")) && (kv.JumpToKey("Settings"))) {
		char custom_msg[IRC_MAXLEN];
		kv.GetString("custom_msg", custom_msg, sizeof(custom_msg), "");
		if (!StrEqual(custom_msg, "")) {
			IRC_MsgFlaggedChannels("ticket", custom_msg);
		}
	}
	kv.Rewind();
	IRC_MsgFlaggedChannels("ticket", "%s (%s) has reported %s (%s) for %s", name, auth, targetname, targetauth, info);
	IRC_MsgFlaggedChannels("ticket", "use %s to #%d <text> - To reply", mynick, GetClientUserId(client));
	PrintToChat(client, "\x01Your report has been sent. Type \x04/reply your text here\x01 to chat with the admins.");
}

public void OnPluginEnd() {
	IRC_CleanUp();
}

// http://bit.ly/defcon
