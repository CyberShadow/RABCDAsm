/*
 *  Copyright (C) 2010 Vladimir Panteleev <vladimir@thecybershadow.net>
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
import std.string;
import swffile;

void main(string[] args)
{
	if (args.length == 1)
		throw new Exception("No file specified");
	foreach (arg; args[1..$])
	{
		scope swf = SWFFile.read(cast(ubyte[])read(arg));
		uint count;
		foreach (ref tag; swf.tags)
			if ((tag.type == TagType.DoABC || tag.type == TagType.DoABC2))
			{
				ubyte[] abc;
				if (tag.type == TagType.DoABC)
					abc = tag.data;
				else
				{
					auto p = tag.data.ptr+4; // skip flags
					while (*p++) {} // skip name
					abc = tag.data[p-tag.data.ptr..$];
				}
				write(getName(arg) ~ .toString(count++) ~ ".abc", abc);
			}
	}
}
