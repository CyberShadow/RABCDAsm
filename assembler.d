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

module assembler;

import std.file;
import std.string;
import std.conv;
import std.path;
import std.exception;
import abcfile;
import asprogram;
import common;

final class Assembler
{
	struct Position
	{
		string filename;
		size_t pos;

		File load()
		{
			File f = File.load(filename);
			f.pos = f.buf.ptr + pos;
			return f;
		}
	}

	struct File
	{
		string filename;
		string buf;
		immutable(char)* pos;
		immutable(char)* end;
		string[] arguments;
		string basePath;

		static File load(string filename, string[] arguments = null)
		{
			return fromFile(filename, cast(string)read(longPath(filename)), arguments);
		}

		static File fromFile(string filename, string data, string[] arguments = null)
		{
			return fromData(filename, data, arguments, dirName(filename));
		}

		static File fromData(string name, string data, string[] arguments = null, string basePath = null)
		{
			data ~= "\0"; data = data[0..$-1]; // hack to prevent readWord etc. from checking for end-of-file on every character
			return File(name, data, data.ptr, data.ptr + data.length, arguments, basePath);
		}

		@property Position position()
		{
			Position p;
			p.filename = filename;
			p.pos = pos - buf.ptr;
			return p;
		}

		@property string positionStr()
		{
			auto lines = splitLines(buf);
			foreach (i, line; lines)
				if (pos <= line.ptr + line.length)
					return format("%s(%d,%d)", filename, i+1, pos-line.ptr+1);
			return format("%s(???)", filename);
		}
	}

	File[64] files;
	int fileCount; /// recursion depth

	string getBasePath()
	{
		foreach (ref file; files[0..fileCount])
			if (file.basePath !is null)
				return file.basePath;
		return null;
	}

	string convertFilename(string filename)
	{
		if (filename.length == 0)
			throw new Exception("Empty filename");
		auto buf = filename.dup;
		foreach (ref c; buf)
			if (c == '\\')
				c = '/';
		return buildPath(getBasePath(), buf);
	}

	void skipWhitespace()
	{
		while (true)
		{
			while (files[0].pos == files[0].end)
				popFile();
			char c = *files[0].pos;
			if (c == ' ' || c == '\r' || c == '\n' || c == '\t')
				files[0].pos++;
			else
			if (c == '#')
				handlePreprocessor();
			else
			if (c == '$')
				handleVar();
			else
			if (c == ';')
			{
				do {} while (*++files[0].pos != '\n');
			}
			else
				return;
		}
	}

	string[string] vars;
	uint[string] namespaceLabels; // for homonym namespaces
	uint sourceVersion = 1;

	void handlePreprocessor()
	{
		skipChar(); // #
		auto word = readWord();
		switch (word)
		{
			case "mixin":
				pushFile(File.fromData("#mixin", readString()));
				break;
			case "call": // #mixin with arguments
				pushFile(File.fromData("#call", readString(), readList!('(', ')', readString, false)()));
				break;
			case "include":
				pushFile(File.load(convertFilename(readString())));
				break;
			case "get":
				auto filename = convertFilename(readString());
				pushFile(File.fromFile(filename, toStringLiteral(cast(string)read(longPath(filename)))));
				break;
			case "set":
				vars[readWord()] = readString();
				break;
			case "unset":
				vars.remove(readWord());
				break;
			case "privatens":
				enforce(sourceVersion < 3, "#privatens is deprecated");
				readUInt();
				readString();
				break;
			case "version":
				sourceVersion = cast(uint)readUInt();
				enforce(sourceVersion >= 1 && sourceVersion <= 3, "Invalid/unknown #version");
				break;
			default:
				files[0].pos -= word.length;
				throw new Exception("Unknown preprocessor declaration: " ~ word);
		}
	}

	void handleVar()
	{
		skipChar();
		skipWhitespace();

		string name;
		bool asStringLiteral;
		if (peekChar() == '"')
		{
			name = readString();
			asStringLiteral = true;
		}
		else
			name = readWord();

		if (name.length == 0)
			throw new Exception("Empty var name");
		if (name[0] >= '1' && name[0] <= '9')
		{
			foreach (ref file; files[0..fileCount])
				if (file.arguments.length)
				{
					uint index = .to!uint(name)-1;
					if (index >= file.arguments.length)
						throw new Exception("Argument index out-of-bounds");
					string value = file.arguments[index];
					pushFile(File.fromData('$' ~ name, asStringLiteral ? toStringLiteral(value) : value));
					return;
				}
			throw new Exception("No arguments in context");
		}
		else
		{
			auto pvalue = name in vars;
			if (pvalue is null)
				throw new Exception("variable " ~ name ~ " is not defined");
			string value = *pvalue;
			pushFile(File.fromData('$' ~ name, asStringLiteral ? toStringLiteral(value) : value));
		}
	}

	static bool isWordChar(char c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '+' || c == '.';
	}

	string readWord()
	{
		skipWhitespace();
		if (!isWordChar(*files[0].pos))
			//throw new Exception("Word character expected");
			return null;
		auto start = files[0].pos;
		char c;
		do
		{
			c = *++files[0].pos;
		} while (isWordChar(c));
		return start[0..files[0].pos-start];
	}

	ubyte fromHex(char x)
	{
		switch (x)
		{
			case '0': return 0;
			case '1': return 1;
			case '2': return 2;
			case '3': return 3;
			case '4': return 4;
			case '5': return 5;
			case '6': return 6;
			case '7': return 7;
			case '8': return 8;
			case '9': return 9;
			case 'a': case 'A': return 10;
			case 'b': case 'B': return 11;
			case 'c': case 'C': return 12;
			case 'd': case 'D': return 13;
			case 'e': case 'E': return 14;
			case 'f': case 'F': return 15;
			default:
				throw new Exception("Malformed hex digit " ~ x);
		}
	}

	void pushFile(File file)
	{
		if (fileCount == files.length)
			throw new Exception("Recursion limit exceeded");
		files[1..fileCount+1] = files[0..fileCount].dup;
		fileCount++;
		files[0] = file;
	}

	/// For restoring the position of an error
	void setFile(File file)
	{
		files[0] = file;
		fileCount = -1;
	}

	void popFile()
	{
		assert(fileCount > 0);
		if (fileCount==1)
			throw new Exception("Unexpected end of file");
		fileCount--;
		files[0..fileCount] = files[1..fileCount+1].dup;
	}

	void expectWord(string expected)
	{
		string word = readWord();
		if (word != expected)
		{
			files[0].pos -= word.length;
			throw new Exception("Expected " ~ expected);
		}
	}

	char peekChar()
	{
		return *files[0].pos;
	}

	void skipChar()
	{
		files[0].pos++;
	}

	void backpedal(size_t amount=1)
	{
		files[0].pos -= amount;
	}

	char readChar()
	{
		skipWhitespace();
		return *files[0].pos++;
	}

	void expectChar(char c)
	{
		if (readChar() != c)
		{
			backpedal();
			throw new Exception("Expected " ~ c);
		}
	}

	// **************************************************

	static void mustBeNull(T)(T obj)
	{
		if (obj !is null)
			throw new Exception("Repeating field declaration");
	}

	static void mustBeSet(string name, T)(T obj)
	{
		if (obj is null)
			throw new Exception(name ~ " not set");
	}

	static ASType toASType(string name)
	{
		auto t = name in ASTypeByName;
		if (t)
			return *t;
		throw new Exception("Unknown ASType " ~ name);
	}

	static void addUnique(string name, K, V)(ref V[K] aa, K k, V v)
	{
		if (k in aa)
			throw new Exception("Duplicate " ~ name);
		aa[k] = v;
	}

	static string toStringLiteral(string str)
	{
		if (str is null)
			return "null";
		else
		{
			static const char[16] hexDigits = "0123456789ABCDEF";

			// TODO: optimize
			string s = "\"";
			foreach (c; str)
				if (c == 0x0A)
					s ~= `\n`;
				else
				if (c == 0x0D)
					s ~= `\r`;
				else
				if (c == '\\')
					s ~= `\\`;
				else
				if (c == '"')
					s ~= `\"`;
				else
				if (c < 0x20)
					s ~= ['\\', 'x', hexDigits[c / 0x10], hexDigits[c % 0x10]];
				else
					s ~= c;
			s ~= '"';
			return s;
		}
	}

	// **************************************************

	ASProgram.Value readValue()
	{
		ASProgram.Value v;
		v.vkind = toASType(readWord());
		expectChar('(');
		switch (v.vkind)
		{
			case ASType.Integer:
				v.vint = readInt();
				break;
			case ASType.UInteger:
				v.vuint = readUInt();
				break;
			case ASType.Double:
				v.vdouble = readDouble();
				break;
			case ASType.Utf8:
				v.vstring = readString();
				break;
			case ASType.Namespace:
			case ASType.PackageNamespace:
			case ASType.PackageInternalNs:
			case ASType.ProtectedNamespace:
			case ASType.ExplicitNamespace:
			case ASType.StaticProtectedNs:
			case ASType.PrivateNamespace:
				v.vnamespace = readNamespace();
				break;
			case ASType.True:
			case ASType.False:
			case ASType.Null:
			case ASType.Undefined:
				break;
			default:
				throw new Exception("Unknown type");
		}
		expectChar(')');
		return v;
	}

	ubyte readFlag(const string[] names)
	{
		auto word = readWord();
		ubyte f = 1;
		for (int i=0; f; i++, f<<=1)
			if (word == names[i])
				return f;
		backpedal(word.length);
		throw new Exception("Unknown flag " ~ word);
	}

	T[] readList(char OPEN, char CLOSE, alias READER, bool ALLOW_NULL, T=typeof(READER()))()
	{
		static if (ALLOW_NULL)
		{
			skipWhitespace();
			if (peekChar() != OPEN)
			{
				auto word = readWord();
				if (word != "null")
				{
					backpedal(word.length);
					throw new Exception("Expected " ~ OPEN ~ " or null");
				}
				return null;
			}
		}

		expectChar(OPEN);
		T[] r;

		skipWhitespace();
		if (peekChar() == CLOSE)
		{
			skipChar(); // CLOSE
			static if (ALLOW_NULL)
			{
				// HACK: give r a .ptr so (r is null) is false, to distinguish it from "null"
				r.length = 1;
				r.length = 0;
				assert(r !is null);
				return r;
			}
			else
				return null;
		}
		while (true)
		{
			r ~= READER();
			char c = readChar();
			if (c == CLOSE)
				break;
			if (c != ',')
			{
				backpedal();
				throw new Exception("Expected " ~ CLOSE ~ " or ,");
			}
		}
		return r;
	}

	// **************************************************

	long readInt()
	{
		string w = readWord();
		if (w == "null")
			return ABCFile.NULL_INT;
		auto v = to!long(w);
		enforce(v >= ABCFile.MIN_INT && v <= ABCFile.MAX_INT, "Int out of bounds");
		return v;
	}

	ulong readUInt()
	{
		string w = readWord();
		if (w == "null")
			return ABCFile.NULL_UINT;
		auto v = to!ulong(w);
		enforce(v <= ABCFile.MAX_UINT, "UInt out of bounds");
		return v;
	}

	double readDouble()
	{
		string w = readWord();
		if (w == "null")
			return ABCFile.NULL_DOUBLE;
		return to!double(w);
	}

	string readString()
	{
		skipWhitespace();
		if (peekChar() != '"')
		{
			string word = readWord();
			if (word == "null")
				return null;
			else
			{
				backpedal(word.length);
				throw new Exception("String literal expected");
			}
		}
		string s = "";
		while (true)
			switch (*++files[0].pos)
			{
				case '"':
					skipChar();
					return s;
				case '\\':
					switch (*++files[0].pos)
					{
						case 'n': s ~= '\n'; break;
						case 'r': s ~= '\r'; break;
						case 'x': s ~= cast(char)((fromHex(*++files[0].pos) << 4) | fromHex(*++files[0].pos)); break;
						default: s ~= *files[0].pos;
					}
					break;
				default:
					s ~= *files[0].pos;
			}
	}

	ASProgram.Namespace readNamespace()
	{
		auto word = readWord();
		if (word == "null")
			return null;
		ASProgram.Namespace n = new ASProgram.Namespace;
		n.kind = toASType(word);
		expectChar('(');
		n.name = readString();
		if (peekChar() == ',')
		{
			skipChar();
			string name = readString();
			auto pindex = name in namespaceLabels;
			if (pindex)
				n.id = *pindex;
			else
				n.id = namespaceLabels[name] = cast(uint)namespaceLabels.length+1;
		}
		expectChar(')');
		return n;
	}

	ASProgram.Namespace[] readNamespaceSet()
	{
		return readList!('[', ']', readNamespace, true)();
	}

	ASProgram.Multiname readMultiname()
	{
		auto word = readWord();
		if (word == "null")
			return null;
		ASProgram.Multiname m = new ASProgram.Multiname;
		m.kind = toASType(word);
		expectChar('(');
		switch (m.kind)
		{
			case ASType.QName:
			case ASType.QNameA:
				m.vQName.ns = readNamespace();
				expectChar(',');
				m.vQName.name = readString();
				break;
			case ASType.RTQName:
			case ASType.RTQNameA:
				m.vRTQName.name = readString();
				break;
			case ASType.RTQNameL:
			case ASType.RTQNameLA:
				break;
			case ASType.Multiname:
			case ASType.MultinameA:
				m.vMultiname.name = readString();
				expectChar(',');
				m.vMultiname.nsSet = readNamespaceSet();
				break;
			case ASType.MultinameL:
			case ASType.MultinameLA:
				m.vMultinameL.nsSet = readNamespaceSet();
				break;
			case ASType.TypeName:
				m.vTypeName.name = readMultiname();
				m.vTypeName.params = readList!('<', '>', readMultiname, false)();
				break;
			default:
				throw new Exception("Unknown Multiname kind");
		}
		expectChar(')');
		return m;
	}

	ASProgram.Class[string] classesByID;
	ASProgram.Method[string] methodsByID;

	struct Fixup(T) { Position where; T* ptr; string name; }
	Fixup!(ASProgram.Class)[] classFixups;
	Fixup!(ASProgram.Method)[] methodFixups;

	ASProgram.Trait readTrait()
	{
		ASProgram.Trait t;
		auto kind = readWord();
		auto pkind = kind in TraitKindByName;
		if (pkind is null)
		{
			backpedal(kind.length);
			throw new Exception("Unknown trait kind");
		}
		t.kind = *pkind;
		t.name = readMultiname();
		switch (t.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				while (true)
				{
					string word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vSlot.slotId = cast(uint)readUInt();
							break;
						case "type":
							mustBeNull(t.vSlot.typeName);
							t.vSlot.typeName = readMultiname();
							break;
						case "value":
							t.vSlot.value = readValue();
							break;
						case "metadata":
							t.metadata ~= readMetadata();
							break;
						case "end":
							return t;
						default:
							throw new Exception("Unknown " ~ kind ~ " trait field " ~ word);
					}
				}
			case TraitKind.Class:
				while (true)
				{
					string word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vClass.slotId = cast(uint)readUInt();
							break;
						case "class":
							mustBeNull(t.vClass.vclass);
							t.vClass.vclass = readClass();
							break;
						case "metadata":
							t.metadata ~= readMetadata();
							break;
						case "end":
							return t;
						default:
							throw new Exception("Unknown " ~ kind ~ " trait field " ~ word);
					}
				}
			case TraitKind.Function:
				while (true)
				{
					string word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vFunction.slotId = cast(uint)readUInt();
							break;
						case "method":
							mustBeNull(t.vFunction.vfunction);
							t.vFunction.vfunction = readMethod();
							break;
						case "metadata":
							t.metadata ~= readMetadata();
							break;
						case "end":
							return t;
						default:
							throw new Exception("Unknown " ~ kind ~ " trait field " ~ word);
					}
				}
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				while (true)
				{
					string word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "dispid":
							t.vMethod.dispId = cast(uint)readUInt();
							break;
						case "method":
							mustBeNull(t.vMethod.vmethod);
							t.vMethod.vmethod = readMethod();
							break;
						case "metadata":
							t.metadata ~= readMetadata();
							break;
						case "end":
							return t;
						default:
							throw new Exception("Unknown " ~ kind ~ " trait field " ~ word);
					}
				}
			default:
				throw new Exception("Unknown trait kind");
		}
	}

	ASProgram.Metadata readMetadata()
	{
		auto metadata = new ASProgram.Metadata;
		metadata.name = readString();
		string[] items;
		while (true)
			switch (readWord())
			{
				case "item":
					items ~= readString();
					items ~= readString();
					break;
				case "end":
					if (sourceVersion < 2)
					{
						metadata.keys   = items[0..$/2];
						metadata.values = items[$/2..$];
					}
					else
					{
						metadata.keys  .length = items.length/2;
						metadata.values.length = items.length/2;
						foreach (i; 0..items.length/2)
						{
							metadata.keys  [i] = items[i*2  ];
							metadata.values[i] = items[i*2+1];
						}
					}
					return metadata;
				default:
					throw new Exception("Expected item or end");
			}
	}

	ASProgram.Method readMethod()
	{
		ASProgram.Method m = new ASProgram.Method;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "name":
					mustBeNull(m.name);
					m.name = readString();
					break;
				case "refid":
					addUnique!("method")(methodsByID, readString(), m);
					break;
				case "param":
					m.paramTypes ~= readMultiname();
					break;
				case "returns":
					mustBeNull(m.returnType);
					m.returnType = readMultiname();
					break;
				case "flag":
					m.flags |= readFlag(MethodFlagNames);
					break;
				case "optional":
					m.options ~= readValue();
					break;
				case "paramname":
					m.paramNames ~= readString();
					break;
				case "body":
					m.vbody = readMethodBody();
					m.vbody.method = m;
					break;
				case "end":
					return m;
				default:
					throw new Exception("Unknown method field " ~ word);
			}
		}
	}

	ASProgram.Instance readInstance()
	{
		ASProgram.Instance i = new ASProgram.Instance;
		i.name = readMultiname();
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "extends":
					mustBeNull(i.superName);
					i.superName = readMultiname();
					break;
				case "implements":
					i.interfaces ~= readMultiname();
					break;
				case "flag":
					i.flags |= readFlag(InstanceFlagNames);
					break;
				case "protectedns":
					mustBeNull(i.protectedNs);
					i.protectedNs = readNamespace();
					break;
				case "iinit":
					mustBeNull(i.iinit);
					i.iinit = readMethod();
					break;
				case "trait":
					i.traits ~= readTrait();
					break;
				case "end":
					mustBeSet!("iinit")(i.iinit);
					return i;
				default:
					throw new Exception("Unknown instance field " ~ word);
			}
		}
	}

	ASProgram.Class readClass()
	{
		ASProgram.Class c = new ASProgram.Class;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "refid":
					addUnique!("class")(classesByID, readString(), c);
					break;
				case "instance":
					mustBeNull(c.instance);
					c.instance = readInstance();
					break;
				case "cinit":
					mustBeNull(c.cinit);
					c.cinit = readMethod();
					break;
				case "trait":
					c.traits ~= readTrait();
					break;
				case "end":
					mustBeSet!("cinit")(c.cinit);
					mustBeSet!("instance")(c.instance);
					return c;
				default:
					throw new Exception("Unknown class field " ~ word);
			}
		}
	}

/+
	ASProgram.Script readScript()
	{
		ASProgram.Script s = new ASProgram.Script;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "end":
					return s;
				default:
					throw new Exception("Unknown script field " ~ word);
			}
		}
	}

+/

	ASProgram.Script readScript()
	{
		ASProgram.Script s = new ASProgram.Script;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "sinit":
					mustBeNull(s.sinit);
					s.sinit = readMethod();
					break;
				case "trait":
					s.traits ~= readTrait();
					break;
				case "end":
					mustBeSet!("sinit")(s.sinit);
					return s;
				default:
					throw new Exception("Unknown script field " ~ word);
			}
		}
	}

	ASProgram.MethodBody readMethodBody()
	{
		uint[string] labels;
		ASProgram.MethodBody m = new ASProgram.MethodBody;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "maxstack":
					m.maxStack = cast(uint)readUInt();
					break;
				case "localcount":
					m.localCount = cast(uint)readUInt();
					break;
				case "initscopedepth":
					m.initScopeDepth = cast(uint)readUInt();
					break;
				case "maxscopedepth":
					m.maxScopeDepth = cast(uint)readUInt();
					break;
				case "code":
					m.instructions = readInstructions(labels);
					break;
				case "try":
					m.exceptions ~= readException(labels);
					break;
				case "trait":
					m.traits ~= readTrait();
					break;
				case "end":
					return m;
				default:
					throw new Exception("Unknown body field " ~ word);
			}
		}
	}

	ABCFile.Label parseLabel(string label, uint[string] labels)
	{
		string name = label;
		int offset = 0;
		foreach (i, c; label)
			if (c=='-' || c=='+')
			{
				name = label[0..i];
				offset = to!int(label[i..$]);
				break;
			}
		auto lp = name in labels;
		if (lp is null)
			throw new Exception("Unknown label " ~ name);

		return ABCFile.Label(*lp, offset);
	}

	ASProgram.Instruction[] readInstructions(ref uint[string] _labels)
	{
		ASProgram.Instruction[] instructions;
		struct LocalFixup { Position where; uint ii, ai; string name; uint si; } // BUG: "pos" won't save correctly in #includes
		LocalFixup[] jumpFixups, switchFixups, localClassFixups, localMethodFixups;
		uint[string] labels;

		while (true)
		{
			auto word = readWord();
			if (word == "end")
				break;
			if (peekChar() == ':')
			{
				addUnique!("label")(labels, word, to!uint(instructions.length));
				skipChar(); // :
				continue;
			}

			auto popcode = word in OpcodeByName;
			if (popcode is null)
			{
				backpedal(word.length);
				throw new Exception("Unknown opcode " ~ word);
			}

			ASProgram.Instruction instruction;
			instruction.opcode = *popcode;
			auto argTypes = opcodeInfo[instruction.opcode].argumentTypes;
			instruction.arguments.length = argTypes.length;
			foreach (uint i, type; argTypes)
			{
				final switch (type)
				{
					case OpcodeArgumentType.Unknown:
						throw new Exception("Don't know how to assemble OP_" ~ opcodeInfo[instruction.opcode].name);

					case OpcodeArgumentType.UByteLiteral:
						instruction.arguments[i].ubytev = to!ubyte(readUInt());
						break;
					case OpcodeArgumentType.IntLiteral:
						instruction.arguments[i].intv = readInt();
						break;
					case OpcodeArgumentType.UIntLiteral:
						instruction.arguments[i].uintv = readUInt();
						break;

					case OpcodeArgumentType.Int:
						instruction.arguments[i].intv = readInt();
						break;
					case OpcodeArgumentType.UInt:
						instruction.arguments[i].uintv = readUInt();
						break;
					case OpcodeArgumentType.Double:
						instruction.arguments[i].doublev = readDouble();
						break;
					case OpcodeArgumentType.String:
						instruction.arguments[i].stringv = readString();
						break;
					case OpcodeArgumentType.Namespace:
						instruction.arguments[i].namespacev = readNamespace();
						break;
					case OpcodeArgumentType.Multiname:
						instruction.arguments[i].multinamev = readMultiname();
						break;
					case OpcodeArgumentType.Class:
						localClassFixups ~= LocalFixup(files[0].position, to!uint(instructions.length), i, readString());
						break;
					case OpcodeArgumentType.Method:
						localMethodFixups ~= LocalFixup(files[0].position, to!uint(instructions.length), i, readString());
						break;

					case OpcodeArgumentType.JumpTarget:
					case OpcodeArgumentType.SwitchDefaultTarget:
						jumpFixups ~= LocalFixup(files[0].position, to!uint(instructions.length), i, readWord());
						break;

					case OpcodeArgumentType.SwitchTargets:
						string[] switchTargetLabels = readList!('[', ']', readWord, false)();
						instruction.arguments[i].switchTargets.length = switchTargetLabels.length;
						foreach (uint li, s; switchTargetLabels)
							switchFixups ~= LocalFixup(files[0].position, to!uint(instructions.length), i, s, li);
						break;
				}
				if (i < argTypes.length-1)
					expectChar(',');
			}

			instructions ~= instruction;
		}

		foreach (ref f; jumpFixups)
		{
			scope(failure) setFile(f.where.load());
			instructions[f.ii].arguments[f.ai].jumpTarget = parseLabel(f.name, labels);
		}

		foreach (ref f; switchFixups)
		{
			scope(failure) setFile(f.where.load());
			instructions[f.ii].arguments[f.ai].switchTargets[f.si] = parseLabel(f.name, labels);
		}

		foreach (ref f; localClassFixups)
			classFixups ~= Fixup!(ASProgram.Class)(f.where, &instructions[f.ii].arguments[f.ai].classv, f.name);
		foreach (ref f; localMethodFixups)
			methodFixups ~= Fixup!(ASProgram.Method)(f.where, &instructions[f.ii].arguments[f.ai].methodv, f.name);

		_labels = labels;
		return instructions;
	}

	ASProgram.Exception readException(uint[string] labels)
	{
		ABCFile.Label readLabel()
		{
			auto word = readWord();
			scope(failure) backpedal(word.length);
			return parseLabel(word, labels);
		}

		ASProgram.Exception e;
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "from":
					e.from = readLabel();
					break;
				case "to":
					e.to = readLabel();
					break;
				case "target":
					e.target = readLabel();
					break;
				case "type":
					e.excType = readMultiname();
					break;
				case "name":
					e.varName = readMultiname();
					break;
				case "end":
					return e;
				default:
					throw new Exception("Unknown exception field " ~ word);
			}
		}
	}

	ASProgram as;

	void readProgram()
	{
		expectWord("program");
		while (true)
		{
			auto word = readWord();
			switch (word)
			{
				case "minorversion":
					as.minorVersion = cast(ushort)readUInt();
					break;
				case "majorversion":
					as.majorVersion = cast(ushort)readUInt();
					break;
				case "script":
					as.scripts ~= readScript();
					break;
				case "class":
					as.orphanClasses ~= readClass();
					break;
				case "method":
					as.orphanMethods ~= readMethod();
					break;
				case "end":
					return;
				default:
					throw new Exception("Unknown program field " ~ word);
			}
		}
	}

	this(ASProgram as)
	{
		this.as = as;
	}

	void assemble(string mainFilename)
	{
		pushFile(File.load(mainFilename));

		try
		{
			readProgram();

			foreach (ref f; classFixups)
				if (f.name is null)
					*f.ptr = null;
				else
				{
					auto cp = f.name in classesByID;
					if (cp is null)
					{
						setFile(f.where.load());
						throw new Exception("Unknown class refid: " ~ f.name);
					}
					*f.ptr = *cp;
				}

			foreach (ref f; methodFixups)
				if (f.name is null)
					*f.ptr = null;
				else
				{
					auto mp = f.name in methodsByID;
					if (mp is null)
					{
						setFile(f.where.load());
						throw new Exception("Unknown method refid: " ~ f.name);
					}
					*f.ptr = *mp;
				}
		}
		catch (Exception e)
		{
			string s = files[0].positionStr ~ ": ";
			if (fileCount == -1)
				s ~= "\n\t(inclusion context unavailable)";
			else
				foreach (ref f; files[1..fileCount])
					s ~= "\n\t(included from " ~ f.positionStr ~ ")";
			throw new Exception(s, e);
		}

		classFixups = null;
		methodFixups = null;
		classesByID = null;
		methodsByID = null;
	}
}
