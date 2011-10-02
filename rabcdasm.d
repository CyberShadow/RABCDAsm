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

module rabcdasm;

import std.file;
import std.path;
import abcfile;
import asprogram;
import disassembler;

void main(string[] args)
{
	if (args.length == 1)
		throw new Exception("No arguments specified");
	foreach (arg; args[1..$])
	{
		scope abc = ABCFile.read(cast(ubyte[])read(arg));
		scope as = ASProgram.fromABC(abc);
		scope disassembler = new Disassembler(as, stripExtension(arg), stripExtension(baseName(arg)));
		disassembler.disassemble();
	}
}
