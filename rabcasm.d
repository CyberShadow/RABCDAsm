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

module rabcasm;

import std.file;
import std.path;
import abcfile;
import asprogram;
import assembler;

void main(string[] args)
{
	if (args.length < 2)
		throw new Exception("No arguments specified.\nUsage: "~args[0]~" directory/file.main.asasm [file.abc]");

	auto as = new ASProgram;
	auto assembler = new Assembler(as);

	string dirmain = args[1];
	string abcfile = setExtension(args[1], "abc");
	if (args.length >= 3) abcfile = args[2];

	assembler.assemble(dirmain);
	auto abc = as.toABC();
	write(abcfile, abc.write());
}
