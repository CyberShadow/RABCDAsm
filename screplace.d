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
		throw new Exception("Bad arguments. Usage: screplace file.swf index SymbolClass.sc");
	auto swf = SWFFile.read(cast(ubyte[])read(args[1]));
	auto index = to!uint(args[2]);
	uint count;
	foreach (ref tag; swf.tags)
		if ((tag.type == TagType.SymbolClass) && count++ == index)
		{
			auto sc = cast(ubyte[])read(args[3]);
			tag.data = sc;
			tag.length = cast(uint)tag.data.length;
			write(args[1], swf.write());
			return;
		}
	throw new Exception("Not enough SymbolClass tags in file");
}
