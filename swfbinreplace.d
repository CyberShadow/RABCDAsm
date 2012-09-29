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

module swfbinreplace;

import std.file;
import std.conv;
import swffile;

void main(string[] args)
{
	if (args.length != 4)
		throw new Exception("Bad arguments. Usage: swfbinreplace file.swf id data.bin");
	auto swf = SWFFile.read(cast(ubyte[])read(args[1]));
	auto id = to!ushort(args[2]);
	foreach (ref tag; swf.tags)
		if (tag.type == TagType.DefineBinaryData && tag.data.length >= 6 && *cast(short*)tag.data.ptr == id)
		{
			auto bin = cast(ubyte[])read(args[3]);
			tag.data = tag.data[0..6] ~ bin;
			tag.length = cast(uint)tag.data.length;
			write(args[1], swf.write());
			return;
		}
	throw new Exception("DefineBinaryData tag with specified ID not found in file");
}
