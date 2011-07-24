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

/// A simple tool to build RABCDAsm in one command.
/// You can use the DC and DCFLAGS environment variables to override the detected compiler and compilation flags.

module build_rabcdasm;

version(D_Version2)
	{ /* All OK */ }
else
	static assert(false, "Unsupported D version.\nThis software requires a D2 ( http://www.digitalmars.com/d/2.0/ ) compiler to build.");

version(DigitalMars)
	const DEFAULT_COMPILER = "dmd";
else
	const DEFAULT_COMPILER = "gdmd";

const DEFAULT_FLAGS = "-w -O -inline";

import std.process;
import std.string;

string[][string] programs;

static this()
{
	programs["rabcasm"      ] = ["abcfile", "asprogram",    "assembler", "autodata", "murmurhash2a"];
	programs["rabcdasm"     ] = ["abcfile", "asprogram", "disassembler", "autodata", "murmurhash2a"];
	programs["abcexport"    ] = ["swffile", "zlibx"];
	programs["abcreplace"   ] = ["swffile", "zlibx"];
	programs["swfbinexport" ] = ["swffile", "zlibx"];
	programs["swfbinreplace"] = ["swffile", "zlibx"];
	programs["swfdecompress"] = ["swffile", "zlibx"];
	programs["swf7zcompress"] = ["swffile", "zlibx"];
}

int main()
{
	string compiler = getenv("DC");
	if (compiler is null)
		compiler = DEFAULT_COMPILER;

	string flags = getenv("DCFLAGS");
	if (flags is null)
		flags = DEFAULT_FLAGS;

	foreach (program, modules; programs)
	{
		int ret = system(format("%s %s %s %s", compiler, flags, program, join(modules, " ")));
		if (ret)
			return ret;
	}

	return 0;
}
