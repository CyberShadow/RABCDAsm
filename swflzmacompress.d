/*
 *  Copyright 2010, 2011, 2012, 2013 Vladimir Panteleev <vladimir@thecybershadow.net>
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

module swflzmacompress;

import std.exception;
import std.file;
import std.getopt;
import std.string;
import swffile;

void main(string[] args)
{
	bool force, updateVersion;
	getopt(args,
		"--force", &force,
		"--update-version", &updateVersion,
	);

	if (args.length == 1)
		throw new Exception("No file specified");
	enum MIN_LZMA_VER = 13;
	foreach (arg; args[1..$])
	{
		auto swf = SWFFile.read(cast(ubyte[])read(arg));
		enforce(swf.header.signature[0] != cast(ubyte)'Z', "Already LZMA-compressed");
		if (swf.header.ver < MIN_LZMA_VER)
		{
			if (updateVersion)
			{
				if (swf.header.ver < 8 && !force)
					throw new Exception(format(
						"SWF version %d has different file format than version %d, " ~
						"required for LZMA. Resulting file may not work. " ~
						"Use --force to override and update version anyway.",
						swf.header.ver, MIN_LZMA_VER
					));
				swf.header.ver = MIN_LZMA_VER;
			}
			else
			if (!force)
				throw new Exception(format(
					"SWF version %d is too old to support SWF LZMA compression, " ~
					"which requires version %d. " ~
					"Use --update-version to update the version number, " ~
					"or --force to compress anyway without updating it.",
					swf.header.ver, MIN_LZMA_VER
				));
		}
		swf.header.signature[0] = cast(ubyte)'Z'; // LZMA
		write(arg, swf.write());
	}
}
