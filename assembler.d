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

module assembler;

import std.file;
import std.string;
import std.conv;
import abcfile;
import asprogram;

final class Assembler
{
	struct File
	{
		string buf;
		char* pos;
		string filename;
	}

	File[] fileStack;

	string buf;
	char* pos;
	char* end;
	string filename;

	void skipWhitespace()
	{
		while (true)
		{
			while (pos == end)
				handleEoF();
			char c = *pos;
			if (c == ' ' || c == '\r' || c == '\n' || c == '\t')
				pos++;
			else
			if (c == '#')
				processPreprocessor();
			else
			if (c == ';')
			{
				do {} while (*++pos != '\n');
			}
			else
				return;	
		}
	}

	bool isWordChar(char c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '+' || c == '.'; // TODO: use lookup table?
	}

	string readWord()
	{
		skipWhitespace();
		if (!isWordChar(*pos))
			//throw new Exception("Word character expected");
			return null;
		auto start = pos;
		char c;
		do
		{
			c = *++pos;
		} while (isWordChar(c));
		return start[0..pos-start];
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

	void processPreprocessor()
	{
		pos++; // #
		auto word = readWord();
		switch (word)
		{
			case "include":
				string newFilename = readString();
				foreach (ref c; newFilename)
					if (c == '\\')
						c = '/';
				newFilename = join(split(filename, "/")[0..$-1] ~ split(newFilename, "/"), "/");
				pushFile();
				loadFile(newFilename);
				break;
			default:
				pos -= word.length;
				throw new Exception("Unknown preprocessor declaration: " ~ word);
		}
	}

	void handleEoF()
	{
		popFile();
	}

	void loadFile(string newFilename)
	{
		filename = newFilename.dup;
		foreach (ref c; filename)
			if (c == '\\')
				c = '/';
		buf = cast(string)read(filename);
		pos = buf.ptr;
		end = buf.ptr + buf.length;
	}

	void pushFile()
	{
		fileStack ~= File(buf, pos, filename);
	}

	void popFile()
	{
		if (fileStack.length == 0)
			throw new Exception("Unexpected end of file");
		auto lastFile = &fileStack[$-1];
		filename = lastFile.filename;
		buf = lastFile.buf;
		pos = lastFile.pos;
		end = buf.ptr + buf.length;
		fileStack = fileStack[0..$-1];
	}

	void expectWord(string expected)
	{
		string word = readWord();
		if (word != expected)
		{
			pos -= word.length;
			throw new Exception("Expected " ~ expected);
		}
	}

	char peek()
	{
		return *pos;
	}

	char readChar()
	{
		skipWhitespace();
		return *pos++;
	}

	void expectChar(char c)
	{
		if (readChar() != c)
		{
			pos--;
			throw new Exception("Expected " ~ c);
		}
	}

	// **************************************************

	static void mustBeNull(T)(T obj)
	{
		if (obj !is null)
			throw new Exception("Repeating field declaration");
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

	ubyte readFlag(string[] names)
	{
		auto word = readWord();
		ubyte f = 1;
		for (int i=0; f; i++, f<<=1)
			if (word == names[i])
				return f;
		pos -= word.length;
		throw new Exception("Unknown flag " ~ word);
	}

	T[] readList(char OPEN, char CLOSE, alias READER, bool ALLOW_NULL, T=typeof(READER()))()
	{
		static if (ALLOW_NULL)
		{
			skipWhitespace();
			if (peek() != OPEN)
			{
				auto word = readWord();
				if (word != "null")
				{
					pos -= word.length;
					throw new Exception("Expected " ~ OPEN ~ " or null");
				}
				return null;
			}
		}

		expectChar(OPEN);
		T[] r;

		skipWhitespace();
		if (peek() == CLOSE)
		{
			pos++; // skip CLOSE
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
				pos--;
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
		return toInt(w);
	}

	ulong readUInt()
	{
		string w = readWord();
		if (w == "null")
			return ABCFile.NULL_UINT;
		return toUint(w);
	}

	double readDouble()
	{
		string w = readWord();
		if (w == "null")
			return ABCFile.NULL_DOUBLE;
		return toDouble(w);
	}

	string readString()
	{
		skipWhitespace();
		if (*pos != '"')
		{
			string word = readWord();
			if (word == "null")
				return null;
			else
			{
				pos -= word.length;
				throw new Exception("String literal expected");
			}
		}
		string s = "";
		while (true)
			switch (*++pos)
			{
				case '"':
					pos++;
					return s;
				case '\\':
					switch (*++pos)
					{
						case 'n': s ~= '\n'; break;
						case 'r': s ~= '\r'; break;
						case 'x': s ~= cast(char)((fromHex(*++pos) << 4) | fromHex(*++pos)); break;
						default: s ~= *pos;
					}
					break;
				default: 
					s ~= *pos;	
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
		if (n.kind == ASType.PrivateNamespace)
		{
			expectChar(',');
			n.privateIndex = cast(uint)readUInt();
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

	struct Fixup(T) { T* ptr; string name; }
	Fixup!(ASProgram.Class)[] classFixups;
	Fixup!(ASProgram.Method)[] methodFixups;

	ASProgram.Trait readTrait()
	{
		ASProgram.Trait t;
		auto kind = readWord();
		auto pkind = kind in TraitKindByName;
		if (pkind is null)
		{
			pos -= kind.length;
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

	ASProgram.Instruction[] readInstructions(ref uint[string] _labels)
	{
		ASProgram.Instruction[] instructions;
		struct LocalFixup { char* pos; uint ii, ai; string name; uint si; } // BUG: "pos" won't save correctly in #includes
		LocalFixup[] jumpFixups, switchFixups, localClassFixups, localMethodFixups;
		uint[string] labels;

		while (true)
		{
			auto word = readWord();
			if (word == "end")
				break;
			if (peek() == ':')
			{
				addUnique!("label")(labels, word, instructions.length);
				pos++; // :
				continue;
			}

			auto popcode = word in OpcodeByName;
			if (popcode is null)
			{
				pos -= word.length;
				throw new Exception("Unknown opcode " ~ word);
			}

			ASProgram.Instruction instruction;
			instruction.opcode = *popcode;
			auto argTypes = opcodeInfo[instruction.opcode].argumentTypes;
			instruction.arguments.length = argTypes.length;
			foreach (i, type; argTypes)
			{
				switch (type)
				{
					case OpcodeArgumentType.Unknown:
						throw new Exception("Don't know how to assemble OP_" ~ opcodeInfo[instruction.opcode].name);

					case OpcodeArgumentType.UByteLiteral:
						instruction.arguments[i].ubytev = cast(ubyte)readUInt();
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
						localClassFixups ~= LocalFixup(pos, instructions.length, i, readString());
						break;
					case OpcodeArgumentType.Method:
						localMethodFixups ~= LocalFixup(pos, instructions.length, i, readString());
						break;

					case OpcodeArgumentType.JumpTarget:
					case OpcodeArgumentType.SwitchDefaultTarget:
						jumpFixups ~= LocalFixup(pos, instructions.length, i, readWord());
						break;

					case OpcodeArgumentType.SwitchTargets:
						string[] switchTargetLabels = readList!('[', ']', readWord, false)();
						instruction.arguments[i].switchTargets = new uint[switchTargetLabels.length];
						foreach (li, s; switchTargetLabels)
							switchFixups ~= LocalFixup(pos, instructions.length, i, s, li);
						break;

					default:
						assert(0);
				}
				if (i < argTypes.length-1)
					expectChar(',');
			}

			instructions ~= instruction;
		}

		foreach (ref f; jumpFixups)
		{
			auto lp = f.name in labels;
			if (lp is null)
			{
				pos = f.pos;
				throw new Exception("Unknown label " ~ f.name);
			}
			instructions[f.ii].arguments[f.ai].jumpTarget = *lp;
		}

		foreach (ref f; switchFixups)
		{
			auto lp = f.name in labels;
			if (lp is null)
			{
				pos = f.pos;
				throw new Exception("Unknown label " ~ f.name);
			}
			instructions[f.ii].arguments[f.ai].switchTargets[f.si] = *lp;
		}

		foreach (ref f; localClassFixups)
			classFixups ~= Fixup!(ASProgram.Class)(&instructions[f.ii].arguments[f.ai].classv, f.name);
		foreach (ref f; localMethodFixups)
			methodFixups ~= Fixup!(ASProgram.Method)(&instructions[f.ii].arguments[f.ai].methodv, f.name);

		_labels = labels;
		return instructions;
	}

	ASProgram.Exception readException(uint[string] labels)
	{
		uint readLabel()
		{
			auto word = readWord();
			auto plabel = word in labels;
			if (plabel is null)
			{
				pos -= word.length;
				throw new Exception("Unknown label " ~ word);
			}
			return *plabel;
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
		loadFile(mainFilename);

		try
			readProgram();
		catch (Object o)
		{
			auto lines = splitlines(buf);
			foreach (i, line; lines)
				if (pos <= line.ptr + line.length)
					throw new Exception(format("%s(%d,%d): %s", filename, i+1, pos-line.ptr+1, o.toString));
			throw new Exception(format("%s(???): %s", filename, o.toString));
		}

		foreach (ref f; classFixups)
		{
			auto cp = f.name in classesByID;
			if (cp is null)
				throw new Exception("Unknown class refid: " ~ f.name);
			*f.ptr = *cp;
		}

		foreach (ref f; methodFixups)
		{
			auto mp = f.name in methodsByID;
			if (mp is null)
				throw new Exception("Unknown method refid: " ~ f.name);
			*f.ptr = *mp;
		}

		classFixups = null;
		methodFixups = null;
		classesByID = null;
		methodsByID = null;
	}
}
