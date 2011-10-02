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

module swfbinexport;

import std.file;
import std.path;
import std.string;
import std.stdio;
import std.exception;
import swffile;

void main(string[] args)
{
	if (args.length == 1)
		throw new Exception("No file specified");
	foreach (arg; args[1..$])
		try
		{
			scope swf = SWFFile.read(cast(ubyte[])read(arg));
			bool found;
			foreach (ref tag; swf.tags)
				if (tag.type == TagType.DefineBinaryData)
				{
					found = true;
					enforce(tag.data.length >= 6);
					ushort id = *cast(short*)tag.data.ptr;
					ubyte[] bin = tag.data[6..$];
					std.file.write(format("%s-%d.bin", stripExtension(arg), id), bin);
				}
			enforce(found, "No DefineBinaryData tags found");
		}
		catch (Exception e)
			writefln("Error while processing %s: %s", arg, e);
}
