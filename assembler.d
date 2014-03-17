/*
 *  Copyright 2010, 2011, 2012, 2013, 2014 Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.conv;
import std.exception;
import std.file;
import std.path;
import std.range;
import std.stdio;
import std.string;

import abcfile;
import asprogram;
import common;

final class Assembler
{
	static struct Position
	{
		File file;
		ulong offset;

		File load()
		{
			assert(file.ptr == file.end);
			file.filePosition = offset;
			return file;
		}
	}

	static final class File
	{
		string name;
		string[] arguments;
		string data;
		@property bool isVirtual() { return data ! is null; }

		File parent;

		const(char)* ptr, end;

		enum BUF_SIZE = 256*1024;
		enum PADDING = 16;
		private char[] buffer;
		static char[][] usedBuffers;

		ulong filePosition; // File position of buffer.ptr
		sizediff_t shift; // Error location adjustment
		std.stdio.File f;

		this(string name, string data = null, string[] arguments = null)
		{
			this.name = name;
			this.arguments = arguments;
			this.data = data;
			if (data)
			{
				createBuffer(data.length);
				buffer[] = data[];
				ptr = buffer.ptr;
				end = ptr + data.length;
			}
			else
			{
				createBuffer(BUF_SIZE);
				f = openFile(name, "rb");
			}
		}

		bool loadNextChunk()
		{
			if (!f.isOpen)
				return false;

			filePosition += end - buffer.ptr;
			assert(filePosition == f.tell, "%s %s".format(filePosition, f.tell));

			auto result = f.rawRead(buffer[0..BUF_SIZE]);
			if (result.length)
			{
				ptr = result.ptr;
				end = ptr + result.length;
				if (result.length < BUF_SIZE)
					buffer[result.length..result.length+PADDING] = 0;
				return true;
			}
			else
			{
				f.close();
				ptr = end = buffer.ptr + buffer.length - PADDING;
				usedBuffers ~= buffer;
				buffer = null;
				return false;
			}
		}

		void createBuffer(size_t size)
		{
			// guarantee that an out-of-bounds access (within a few bytes)
			// will result in a null character, as an optimization
			auto bufferSize = size + PADDING;
			if (usedBuffers.length && usedBuffers[0].length >= bufferSize)
			{
				buffer = usedBuffers[0];
				usedBuffers = usedBuffers[1..$];
			}
			else
				buffer = new char[bufferSize];
			ptr = end = buffer.ptr;
			buffer[] = 0;
		}

		@property Position position()
		{
			return Position(this, filePosition + (buffer ? ptr - buffer.ptr : 0) + shift);
		}

		@property string positionStr()
		{
			auto offset = position.offset;
			ulong p = 0;
			ulong line = 1;
			ulong lineStart = 0;

			InputRange!(ubyte[]) dataSource;
			if (isVirtual)
				dataSource = (cast(ubyte[])data).only.inputRangeObject;
			else
			{
				f = openFile(name, "rb");
				dataSource = f.byChunk(BUF_SIZE).inputRangeObject;
			}
			scope(exit) if (!isVirtual) f.close();

			foreach (ubyte[] buffer; dataSource)
				foreach (b; buffer)
				{
					if (p == offset)
						return "%s(%d,%d)".format(name, line, p-lineStart+1);
					p++;
					if (b == 10)
					{
						line++;
						lineStart = p;
					}
				}
			return "%s(???)".format(name);
		}

		@property char front()
		{
			char c;
			return (c = *ptr) != 0 ? c : (loadNextChunk(), *ptr);
		}

		void popFront()
		{
			ptr++;
		}
	}

	File currentFile;

	string getBasePath()
	{
		for (auto f = currentFile; f; f = f.parent)
			if (!f.isVirtual)
				return f.name.dirName();
		return null;
	}

	string convertFilename(in char[] filename)
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
			char c;
			while ((c = peekChar())==0)
				popFile();
			if (c == ' ' || c == '\r' || c == '\n' || c == '\t')
				skipChar();
			else
			if (c == '#')
				handlePreprocessor();
			else
			if (c == '$')
				handleVar();
			else
			if (c == ';')
				do
					skipChar();
				while (peekChar() != '\n');
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
				pushFile(new File("#mixin", readImmString()));
				break;
			case "call": // #mixin with arguments
				pushFile(new File("#call", readImmString(), readList!('(', ')', readImmString, false)()));
				break;
			case "include":
				pushFile(new File(convertFilename(readString())));
				break;
			case "get":
				auto filename = convertFilename(readString());
				pushFile(new File(filename, toStringLiteral(cast(string)read(longPath(filename)))));
				break;
			case "set":
				vars[readWord()] = readImmString();
				break;
			case "unset":
				vars.remove(readWord().idup);
				break;
			case "privatens":
				enforce(sourceVersion < 3, "#privatens is deprecated");
				readUInt();
				readString();
				break;
			case "version":
				sourceVersion = readUInt().to!uint();
				enforce(sourceVersion >= 1 && sourceVersion <= 3, "Invalid/unknown #version");
				break;
			default:
				backpedal(word.length);
				throw new Exception("Unknown preprocessor declaration: " ~ word.idup);
		}
	}

	void handleVar()
	{
		skipChar(); // $
		skipWhitespace();

		const(char)[] name;
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
			for (auto f = currentFile; f; f = f.parent)
				if (f.arguments.length)
				{
					uint index = .to!uint(name)-1;
					if (index >= f.arguments.length)
						throw new Exception("Argument index out-of-bounds");
					string value = f.arguments[index];
					pushFile(new File('$' ~ name.assumeUnique(), asStringLiteral ? toStringLiteral(value) : value));
					return;
				}
			throw new Exception("No arguments in context");
		}
		else
		{
			auto pvalue = name in vars;
			if (pvalue is null)
				throw new Exception("variable %s is not defined".format(name));
			string value = *pvalue;
			pushFile(new File('$' ~ name.assumeUnique(), asStringLiteral ? toStringLiteral(value) : value));
		}
	}

	static bool isWordChar(char c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '+' || c == '.';
	}

	const(char)[] readWord()
	{
		skipWhitespace();
		if (!isWordChar(currentFile.front))
			//throw new Exception("Word character expected");
			return null;
		auto b = getBuf();
		while (true)
		{
			auto c = currentFile.front;
			if (!isWordChar(c))
				break;
			b.put(c);
			currentFile.popFront();
		}
		return b.get();
	}
	string readImmWord() { return readWord().idup; }

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
		file.parent = currentFile;
		currentFile = file;
	}

	/// For restoring the position of an error
	void setFile(File file)
	{
		currentFile = file;
	}

	void popFile()
	{
		if (!currentFile || !currentFile.parent)
			throw new Exception("Unexpected end of file");
		currentFile = currentFile.parent;
	}

	void expectWord(string expected)
	{
		auto word = readWord();
		if (word != expected)
		{
			backpedal(word.length);
			throw new Exception("Expected " ~ expected);
		}
	}

	char peekChar()
	{
		return currentFile.front;
	}

	void skipChar()
	{
		currentFile.popFront();
	}

	void backpedal(size_t amount=1)
	{
		currentFile.shift -= amount;
	}

	char readChar()
	{
		auto c = currentFile.front;
		if (c)
			currentFile.popFront;
		return c;
	}

	char readSymbol()
	{
		skipWhitespace();
		return readChar();
	}

	void expectSymbol(char c)
	{
		if (readSymbol() != c)
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

	static ASType toASType(in char[] name)
	{
		auto t = name in ASTypeByName;
		if (t)
			return *t;
		throw new Exception("Unknown ASType %s".format(name));
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
		expectSymbol('(');
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
				v.vstring = readImmString();
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
		expectSymbol(')');
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
		throw new Exception("Unknown flag %s".format(word));
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

		expectSymbol(OPEN);
		auto a = appender!(T[]);

		skipWhitespace();
		if (peekChar() == CLOSE)
		{
			skipChar(); // CLOSE
			static if (ALLOW_NULL)
			{
				static T[1] sr;
				// HACK: give r a .ptr so (r is null) is false, to distinguish it from "null"
				auto r = sr[0..0];
				assert(r !is null);
				return r;
			}
			else
				return null;
		}
		while (true)
		{
			a.put(READER());
			char c = readSymbol();
			if (c == CLOSE)
				break;
			if (c != ',')
			{
				backpedal();
				throw new Exception("Expected " ~ CLOSE ~ " or ,");
			}
		}
		return a.data;
	}

	// **************************************************

	long readInt()
	{
		auto w = readWord();
		if (w == "null")
			return ABCFile.NULL_INT;
		auto v = to!long(w);
		enforce(v >= ABCFile.MIN_INT && v <= ABCFile.MAX_INT, "Int out of bounds");
		return v;
	}

	ulong readUInt()
	{
		auto w = readWord();
		if (w == "null")
			return ABCFile.NULL_UINT;
		auto v = to!ulong(w);
		enforce(v <= ABCFile.MAX_UINT, "UInt out of bounds");
		return v;
	}

	double readDouble()
	{
		auto w = readWord();
		if (w == "null")
			return ABCFile.NULL_DOUBLE;
		return to!double(w);
	}

	const(char)[] readString()
	{
		skipWhitespace();
		char c = readSymbol();
		if (c != '"')
		{
			auto word = readWord();
			if (c == 'n' && word == "ull")
				return null;
			else
			{
				backpedal(1 + word.length);
				throw new Exception("String literal expected");
			}
		}
		auto buf = getBuf();
		while (true)
			switch (c = readChar())
			{
				case '"':
					return buf.get();
				case '\\':
					switch (c = readChar())
					{
						case 'n': buf.put('\n'); break;
						case 'r': buf.put('\r'); break;
						case 'x':
						{
							char c0 = readChar();
							char c1 = readChar();
							buf.put(cast(char)((fromHex(c0) << 4) | fromHex(c1)));
							break;
						}
						default : buf.put(c);
					}
					break;
				case 0:
					throw new Exception("Unexpected null/terminator");
				default:
					buf.put(c);
			}
	}

	StringPool stringPool;
	string readImmString() { return stringPool.get(readString()); }

	Pool!(ASProgram.Namespace, ASType, string, uint) namespacePool;

	ASProgram.Namespace readNamespace()
	{
		auto word = readWord();
		if (word == "null")
			return null;
		auto kind = toASType(word);
		expectSymbol('(');
		auto name = readImmString();
		uint id;
		if (peekChar() == ',')
		{
			skipChar();
			string s = readImmString();
			auto pindex = s in namespaceLabels;
			if (pindex)
				id = *pindex;
			else
				id = namespaceLabels[s] = cast(uint)namespaceLabels.length+1;
		}
		expectSymbol(')');

		static ASProgram.Namespace createNamespace(ASType kind, string name, uint id)
		{
			ASProgram.Namespace n = new ASProgram.Namespace;
			n.kind = kind;
			n.name = name;
			n.id = id;
			return n;
		}
		return namespacePool.get(kind, name, id, &createNamespace);
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
		expectSymbol('(');
		switch (m.kind)
		{
			case ASType.QName:
			case ASType.QNameA:
				m.vQName.ns = readNamespace();
				expectSymbol(',');
				m.vQName.name = readImmString();
				break;
			case ASType.RTQName:
			case ASType.RTQNameA:
				m.vRTQName.name = readImmString();
				break;
			case ASType.RTQNameL:
			case ASType.RTQNameLA:
				break;
			case ASType.Multiname:
			case ASType.MultinameA:
				m.vMultiname.name = readImmString();
				expectSymbol(',');
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
		expectSymbol(')');
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
		kind = TraitKindNames[t.kind];
		t.name = readMultiname();
		switch (t.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				while (true)
				{
					auto word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vSlot.slotId = readUInt().to!uint();
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
							throw new Exception("Unknown %s trait field %s".format(kind, word));
					}
				}
			case TraitKind.Class:
				while (true)
				{
					auto word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vClass.slotId = readUInt().to!uint();
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
							throw new Exception("Unknown %s trait field %s".format(kind, word));
					}
				}
			case TraitKind.Function:
				while (true)
				{
					auto word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "slotid":
							t.vFunction.slotId = readUInt().to!uint();
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
							throw new Exception("Unknown %s trait field %s".format(kind, word));
					}
				}
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				while (true)
				{
					auto word = readWord();
					switch (word)
					{
						case "flag":
							t.attr |= readFlag(TraitAttributeNames);
							break;
						case "dispid":
							t.vMethod.dispId = readUInt().to!uint();
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
							throw new Exception("Unknown %s trait field %s".format(kind, word));
					}
				}
			default:
				throw new Exception("Unknown trait kind");
		}
	}

	ASProgram.Metadata readMetadata()
	{
		auto metadata = new ASProgram.Metadata;
		metadata.name = readImmString();
		string[] items;
		while (true)
			switch (readWord())
			{
				case "item":
					items ~= readImmString();
					items ~= readImmString();
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
					m.name = readImmString();
					break;
				case "refid":
					addUnique!("method")(methodsByID, readImmString(), m);
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
					m.paramNames ~= readImmString();
					break;
				case "body":
					m.vbody = readMethodBody();
					m.vbody.method = m;
					break;
				case "end":
					return m;
				default:
					throw new Exception("Unknown method field %s".format(word));
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
					throw new Exception("Unknown instance field %s".format(word));
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
					addUnique!("class")(classesByID, readImmString(), c);
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
					throw new Exception("Unknown class field %s".format(word));
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
					throw new Exception("Unknown script field %s".format(word));
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
					m.maxStack = readUInt().to!uint();
					break;
				case "localcount":
					m.localCount = readUInt().to!uint();
					break;
				case "initscopedepth":
					m.initScopeDepth = readUInt().to!uint();
					break;
				case "maxscopedepth":
					m.maxScopeDepth = readUInt().to!uint();
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
					throw new Exception("Unknown body field %s".format(word));
			}
		}
	}

	ABCFile.Label parseLabel(const(char)[] label, uint[string] labels)
	{
		auto name = label;
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
			throw new Exception("Unknown label %s".format(name));

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
				addUnique!("label")(labels, word.idup, to!uint(instructions.length));
				skipChar(); // :
				continue;
			}

			auto popcode = word in OpcodeByName;
			if (popcode is null)
			{
				backpedal(word.length);
				throw new Exception("Unknown opcode %s".format(word));
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
						instruction.arguments[i].stringv = readImmString();
						break;
					case OpcodeArgumentType.Namespace:
						instruction.arguments[i].namespacev = readNamespace();
						break;
					case OpcodeArgumentType.Multiname:
						instruction.arguments[i].multinamev = readMultiname();
						break;
					case OpcodeArgumentType.Class:
						localClassFixups ~= LocalFixup(currentFile.position, to!uint(instructions.length), i, readImmString());
						break;
					case OpcodeArgumentType.Method:
						localMethodFixups ~= LocalFixup(currentFile.position, to!uint(instructions.length), i, readImmString());
						break;

					case OpcodeArgumentType.JumpTarget:
					case OpcodeArgumentType.SwitchDefaultTarget:
						jumpFixups ~= LocalFixup(currentFile.position, to!uint(instructions.length), i, readWord().idup);
						break;

					case OpcodeArgumentType.SwitchTargets:
						string[] switchTargetLabels = readList!('[', ']', readImmWord, false)();
						instruction.arguments[i].switchTargets.length = switchTargetLabels.length;
						foreach (uint li, s; switchTargetLabels)
							switchFixups ~= LocalFixup(currentFile.position, to!uint(instructions.length), i, s, li);
						break;
				}
				if (i < argTypes.length-1)
					expectSymbol(',');
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
					throw new Exception("Unknown exception field %s".format(word));
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
					as.minorVersion = readUInt().to!ushort();
					break;
				case "majorversion":
					as.majorVersion = readUInt().to!ushort();
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
					throw new Exception("Unknown program field %s".format(word));
			}
		}
	}

	this(ASProgram as)
	{
		this.as = as;
	}

	string context()
	{
		string s = currentFile.positionStr ~ ": ";
		for (auto f = currentFile.parent; f; f = f.parent)
			s ~= "\n\t(included from %s)".format(f.positionStr);
		return s;
	}

	void assemble(string mainFilename)
	{
		pushFile(new File(mainFilename));

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
			e.msg = "\n%s\n%s".format(context(), e.msg);
			throw e;
		}

		classFixups = null;
		methodFixups = null;
		classesByID = null;
		methodsByID = null;
	}
}

struct StackBuf
{
	enum BUF_COUNT = 16;
	enum BUF_SIZE = 1024;
	static char[BUF_SIZE][BUF_COUNT] bufStorage;
	static char[][BUF_COUNT] buffers;
	static uint counter;

	static this()
	{
		foreach (n; 0..BUF_COUNT)
			buffers[n] = bufStorage[n][];
	}

	static StackBuf create()
	{
		StackBuf b;
		b.buffer = &buffers[counter++ % BUF_COUNT];
		assert((*b.buffer).length);
		b.setBuffer();
		return b;
	}

	void setBuffer()
	{
		ptr = (*buffer).ptr;
		end = ptr + (*buffer).length;
	}

	char[]* buffer;
	char* ptr, end;

	void put(char c)
	{
		if (ptr == end)
		{
			auto len = (*buffer).length;
			buffer.length = len * 2;
			setBuffer();
			ptr += len;
		}
		*ptr++ = c;
	}

	char[] get()
	{
		return (*buffer)[0..ptr-(*buffer).ptr];
	}
}
alias StackBuf.create getBuf;

struct StringPool
{
	string[string] pool;

	string get(in char[] s)
	{
		if (s is null)
			return null;
		auto p = s in pool;
		if (p)
			return *p;
		auto i = s.idup;
		if (i is null)
			i = ""[0..0];
		assert(i !is null);
		return pool[i] = i;
	}
}

struct Pool(T, IndexTypes...)
{
	struct Data
	{
		IndexTypes indices;
	}

	T[Data] pool;

	T get(IndexTypes indices, T function(IndexTypes) ctor)
	{
		auto data = Data(indices);
		auto p = data in pool;
		if (p)
			return *p;
		return pool[data] = ctor(indices);
	}
}
