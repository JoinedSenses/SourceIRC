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

#undef REQUIRE_PLUGIN
#include <sourceirc>

KeyValues
	kv;

public Plugin myinfo = {
	name = "SourceIRC -> Hostmasks",
	author = "Azelphur",
	description = "Provides access based on hostmask",
	version = IRC_VERSION,
	url = "http://Azelphur.com/project/sourceirc"
}

public void OnConfigsExecuted() {
	kv = new KeyValues("SourceIRC");
	char file[512];
	BuildPath(Path_SM, file, sizeof(file), "configs/sourceirc.cfg");
	kv.ImportFromFile(file);
}

public void IRC_RetrieveUserFlagBits(const char[] hostmask, int &flagbits) {
	if (!kv.JumpToKey("Access")) {
		return;
	}
	if (!kv.JumpToKey("Hostmasks")) {
		return;
	}
	if (!kv.GotoFirstSubKey(false)) {
		return;
	}
	char
		key[64]
		, value[64];
	AdminFlag
		tempflag;
	do {
		kv.GetSectionName(key, sizeof(key));
		if (IsWildCardMatch(hostmask, key)) {
			kv.GetString(NULL_STRING, value, sizeof(value));
			for (int i; i <= strlen(value); i++) {
				if (FindFlagByChar(value[i], tempflag)) {
					flagbits |= 1 << view_as<int>(tempflag);
				}
			}
		}
	} while (kv.GotoNextKey(false));

	kv.Rewind();
}

// http://bit.ly/defcon
