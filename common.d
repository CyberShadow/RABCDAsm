/*
 *  Copyright 2012, 2014 Vladimir Panteleev <vladimir@thecybershadow.net>
 *  This file is part of RABCDAsm.
 *
 *  RABCDAsm is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  RABCDAsm is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with RABCDAsm.  If not, see <http://www.gnu.org/licenses/>.
 */

module common;

import std.array;
import std.path;
import std.stdio;
import std.string;

string longPath(string s)
{
	version(Windows)
	{
		if (s.startsWith(`\\`))
			return s;
		else
			return `\\?\` ~ s.absolutePath().buildNormalizedPath().replace(`/`, `\`);
	}
	else
		return s;
}

File openFile(string fn, string mode)
{
	File f;
	static if (is(typeof(&f.windowsHandleOpen)))
	{
		import core.sys.windows.windows;

		import std.exception;
		import std.utf;
		import std.windows.syserror;

		string winMode;
		foreach (c; mode)
			switch (c)
			{
				case 'r':
				case 'w':
				case 'a':
				case '+':
					winMode ~= c;
					break;
				case 'b':
				case 't':
					break;
				default:
					assert(false, "Unknown character in mode");
			}
		DWORD access, creation;
		bool append;
		switch (winMode)
		{
			case "r" : access = GENERIC_READ                ; creation = OPEN_EXISTING; break;
			case "r+": access = GENERIC_READ | GENERIC_WRITE; creation = OPEN_EXISTING; break;
			case "w" : access =                GENERIC_WRITE; creation = OPEN_ALWAYS  ; break;
			case "w+": access = GENERIC_READ | GENERIC_WRITE; creation = OPEN_ALWAYS  ; break;
			case "a" : access =                GENERIC_WRITE; creation = OPEN_ALWAYS  ; append = true; break;
			case "a+": assert(false, "Not implemented"); // requires two file pointers
			default: assert(false, "Bad file mode: " ~ mode);
		}

		auto pathW = toUTF16z(longPath(fn));
		auto h = CreateFileW(pathW, access, FILE_SHARE_READ, null, creation, 0, HANDLE.init);
		enforce(h != INVALID_HANDLE_VALUE, "Failed to open file \"" ~ fn ~ "\": " ~ sysErrorString(GetLastError()));

		assert(!append, "'a' mode not implemented");

		f.windowsHandleOpen(h, mode);
	}
	else
		f.open(fn, mode);
	return f;
}
