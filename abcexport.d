/*
 *  Copyright 2010, 2011 Vladimir Panteleev <vladimir@thecybershadow.net>
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

module abcexport;

import std.file;
import std.path;
import std.conv;
import std.stdio;

import swffile;

void main(string[] args)
{
	//check args
	if ((args.length < 2 || args.length > 3) ||
	    (args[1] == "-h" || args[1] == "--help"))
		throw new Exception("Usage: " ~ args[0] ~ " input.swf <prefix for ABC files>");

	//parse args
	string flashfile = args[1];
	string prefix    = "";
	if (args.length >= 3) prefix = args[2];

	//process flash file
	try {
		scope swf = SWFFile.read(cast(ubyte[])read(flashfile));
		uint count = 0;
		foreach (ref tag; swf.tags)
			if ((tag.type == TagType.DoABC || tag.type == TagType.DoABC2)) {
				ubyte[] abc;
				if (tag.type == TagType.DoABC)
					abc = tag.data;
				else { //DoABC2
					auto p = tag.data.ptr+4; // skip flags
					while (*p++) {} // skip name
					writeln();
					abc = tag.data[p-tag.data.ptr..$];
				}

				//write ABC to file
				std.file.write(prefix ~ stripExtension(flashfile) ~ "-" ~ to!string(count++) ~ ".abc", abc);
			}

		if (count == 0)
			writeln("Processed successfully, but no DoABC tags found.");
		else
			writefln("Processed successfully, %s DoABC tags found.", count);
	} catch (Exception e) {
		writeln("Error while processing:");
		throw e;
	}
}
