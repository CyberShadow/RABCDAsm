/*
 *  Copyright 2010, 2011, 2012 Vladimir Panteleev <vladimir@thecybershadow.net>
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

module abcreplace;

import std.file;
import std.conv;
import swffile;

void main(string[] args)
{
	if (args.length != 4)
		throw new Exception("Bad arguments. Usage: abcreplace file.swf index code.abc");
	auto swf = SWFFile.read(cast(ubyte[])read(args[1]));
	auto index = to!uint(args[2]);
	uint count;
	foreach (ref tag; swf.tags)
		if ((tag.type == TagType.DoABC || tag.type == TagType.DoABC2) && count++ == index)
		{
			auto abc = cast(ubyte[])read(args[3]);
			if (tag.type == TagType.DoABC)
				tag.data = abc;
			else
			{
				auto p = tag.data.ptr+4; // skip flags
				while (*p++) {} // skip name
				tag.data = tag.data[0..p-tag.data.ptr] ~ abc;
			}
			tag.length = cast(uint)tag.data.length;
			write(args[1], swf.write());
			return;
		}
	throw new Exception("Not enough DoABC tags in file");
}
