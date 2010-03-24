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

module swfdecompress;

import std.file;
import std.zlib;
import swffile;

void main(string[] args)
{
	if (args.length == 1)
		throw new Exception("No file specified");
	foreach (arg; args[1..$])
	{
		auto swf = cast(ubyte[])read(arg);
		auto header = cast(SWFFile.Header*)swf.ptr;
		if (header.signature[0] == cast(ubyte)'F')
			throw new Exception("Already uncompressed");
		if (header.signature[0] != cast(ubyte)'C')
			throw new Exception("Unknown format");
		header.signature[0] = cast(ubyte)'F'; // uncompressed
		write(arg, swf[0..8] ~ cast(ubyte[])uncompress(swf[8..$], header.fileLength-8));
	}
}
