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

module swf7zcompress;

import std.file;
import std.process;
import std.zlib;
import swffile;
import zlibx;

ubyte[] gzip2zlib(ubyte[] data, uint adler)
{
	enum
	{
		FTEXT = 1,
		FHCRC = 2,
		FEXTRA = 4,
		FNAME = 8,
		FCOMMENT = 16
	}

	if (data.length < 10 || data[0] != 0x1F || data[1] != 0x8B || data[2] != 0x08)
		throw new Exception("Bad or unsupported gzip format");
	ubyte flags = data[3];
	auto p = data.ptr;
	p += 10; // header size
	if (flags & (FHCRC | FEXTRA | FCOMMENT))
		throw new Exception("Unsupported gzip flags");
	if (flags & FNAME)
		while (*p++) {}

	ubyte[] chdr = [0x78, 0xDA]; // 11011010
	return chdr ~ data[p-data.ptr..data.length-8] ~ cast(ubyte[])[adler];
}

void main(string[] args)
{
	if (args.length == 1)
		throw new Exception("No file specified");
	foreach (arg; args[1..$])
	{
		auto swf = cast(ubyte[])read(arg);
		auto header = cast(SWFFile.Header*)swf.ptr;
		ubyte[] data;
		if (header.signature[0] == cast(ubyte)'C')
			data = exactUncompress(swf[8..$], header.fileLength-8);
		else
		if (header.signature[0] == cast(ubyte)'F')
		{
			data = swf[8..$];
			header.signature[0] = cast(ubyte)'C';
		}
		else
			throw new Exception("Unknown format");
		if (header.fileLength != data.length + 8)
			throw new Exception("Incorrect file length in file header");
		write(arg ~ ".tempdata", data);
		if (system(`7z a -tgzip -mx=9 -mfb=258 "` ~ arg ~ `.tempdata.gz" "` ~ arg ~ `.tempdata"`) || !exists(arg ~ ".tempdata.gz"))
			throw new Exception("7-Zip failed");
		remove(arg ~ ".tempdata");
		auto gzipdata = cast(ubyte[])read(arg ~ ".tempdata.gz");
		remove(arg ~ ".tempdata.gz");
		auto zlibdata = gzip2zlib(gzipdata, adler32(0, data));
		swf = swf[0..8] ~ zlibdata;
		write(arg, swf);
	}
}
