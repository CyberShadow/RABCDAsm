/*
 *  Copyright 2010, 2011, 2012, 2013, 2016 Vladimir Panteleev <vladimir@thecybershadow.net>
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
/// You can also pass program names or compilation options on the command-line to override the default ones.

module build_rabcdasm;

version(D_Version2)
	{ /* All OK */ }
else
	static assert(false, "Unsupported D version.\nThis software requires a D2 ( http://dlang.org/ ) compiler to build.");

version(D_Version2):

version(DigitalMars)
	const DEFAULT_COMPILER = "dmd";
else
	const DEFAULT_COMPILER = "gdmd";

const DEFAULT_FLAGS = "-O -inline";
const LZMA_FLAGS = ["-version=HAVE_LZMA"];

import std.exception;
import std.file;
import std.process;
import std.stdio;
import std.string;

string compiler;
string[] flags;

void compile(string program)
{
	stderr.writeln("* Building ", program);
	enforce(spawnProcess(["rdmd", "--build-only", "--compiler=" ~ compiler] ~ flags ~ program).wait() == 0, "Compilation of " ~ program ~ " failed");
}

void test(string code, in string[] extraFlags=null)
{
	const BASE = "build_rabcdasm_buildtest";
	const FN = BASE ~ ".d";
	std.file.write(FN, code);
	scope(exit) foreach (de; dirEntries(".", BASE ~ "*", SpanMode.shallow)) remove(de.name);
	enforce(spawnProcess(["rdmd", "--force", "--compiler=" ~ compiler, "-od."] ~ flags ~ extraFlags ~ FN).wait() == 0, "Test failed");
	stderr.writeln(" >>> OK");
}

void testBug(string description, int bugId, string code)
{
	stderr.writefln("* Checking for compiler bug %d...", bugId);
	scope(failure)
	{
		stderr.writefln("Compiler bug detected: %s ( https://issues.dlang.org/show_bug.cgi?id=%d ).", description, bugId);
		stderr.writeln("Try again with a different D compiler, compiler version, or build flags (DCFLAGS environment variable)");
	}
	test(code);
}

int main(string[] args)
{
	try
	{
		auto programs = ["rabcasm", "rabcdasm", "abcexport", "abcreplace", "swfbinexport", "swfbinreplace", "swfdecompress", "swf7zcompress"];

		compiler = environment.get("DC", DEFAULT_COMPILER);
		flags = environment.get("DCFLAGS", DEFAULT_FLAGS).split(" ");

		string[] optionArgs, programArgs;
		foreach (arg; args[1..$])
			(arg.startsWith("-") ? optionArgs : programArgs) ~= arg;

		if (optionArgs.length)
			flags = optionArgs;
		if (programArgs.length)
			programs = programArgs;

		stderr.writeln("* Checking for working compiler...");
		test(`
			void main() {}
		`);

		testBug("[REG 2.064] Wrong code with -O on x86_64 for char comparisons", 11508, `
			import assembler; int main() { foreach (c; "_") if (!Assembler.isWordChar(c)) return 1; return 0; }
		`);
		testBug("[REG 2.069] Wrong double-to-string conversion with -O", 15861, `
			import std.format; int main() { return format("%.18g", 4286853117.0) == "4286853117" ? 0 : 1; }
		`);

		bool haveLZMA;

		stderr.writeln("* Checking for LZMA...");
		try
		{
			test(`
				import lzma, std.exception;
				void main()
				{
					LZMAHeader header;
					auto data = cast(immutable(ubyte)[])"Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.";
					auto cdata = lzmaCompress(data, &header);
					header.decompressedSize = data.length;
					auto ddata = lzmaDecompress(header, cdata);
					enforce(data == ddata);
				}
			`, LZMA_FLAGS);

			// Test succeeded
			haveLZMA = true;
		}
		catch (Exception e)
			stderr.writeln(" >>> LZMA not found, building without LZMA support.");

		if (haveLZMA)
			flags ~= LZMA_FLAGS;

		foreach (program; programs)
			compile(program);

		if (haveLZMA)
			compile("swflzmacompress");

		return 0;
	}
	catch (Exception e)
	{
		stderr.writeln("Error: ", e.msg);
		return 1;
	}
}
