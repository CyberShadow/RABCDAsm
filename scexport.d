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
	if (args.length == 1)
		throw new Exception("No file specified");
	foreach (arg; args[1..$])
		try
		{
			scope swf = SWFFile.read(cast(ubyte[])read(arg));
			uint count = 0;
			foreach (ref tag; swf.tags)
				if (tag.type == TagType.SymbolClass)
				{
					ubyte[] abc;
					abc = tag.data;
					std.file.write(stripExtension(arg) ~ "-" ~ to!string(count++) ~ ".sc", abc);
					break;
				}
			if (count == 0)
				throw new Exception("No SymbolClass tags found");
		}
		catch (Exception e)
			writefln("Error while processing %s: %s", arg, e);
}
