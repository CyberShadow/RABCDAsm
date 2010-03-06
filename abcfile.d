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

module abcfile;

import std.stream;

/** 
 * Implements a shallow representation of an .abc file. 
 * Loading and saving an .abc file using this class should produce 
 * output identical to the input.
 */

class ABCFile
{
	ushort minorVersion, majorVersion;
	
	long[] ints;
	ulong[] uints;
	double[] doubles;
	string[] strings;
	Namespace[] namespaces;
	uint[][] namespaceSets;
	Multiname[] multinames;

	MethodInfo[] methods;
	Metadata[] metadata;
	Instance[] instances;
	Class[] classes;
	Script[] scripts;
	MethodBody[] bodies;

	struct Namespace
	{
		Constant kind;
		uint name;
	}

	struct Multiname
	{
		Constant kind;
		union
		{
			struct _QName
			{
				uint ns, name;
			} _QName QName;
			struct _RTQName
			{
				uint name;
			} _RTQName RTQName;
			struct _RTQNameL
			{
			} _RTQNameL RTQNameL;
			struct _Multiname
			{
				uint name, nsSet;
			} _Multiname Multiname;
			struct _MultinameL
			{
				uint nsSet;
			} _MultinameL MultinameL;
			struct _TypeName
			{
				uint name;
				uint[] params;
			} _TypeName TypeName;
		}
	}

	struct MethodInfo
	{
		uint[] params;
		uint returnType;
		uint name;
		ubyte flags; // MethodFlags bitmask
		OptionDetail[] options;
		uint[] paramNames;
	}

	struct OptionDetail
	{
		uint val;
		Constant kind;
	}

	struct Metadata
	{
		struct Item
		{
			uint key, value;
		}

		uint name;
		Item[] items;
	}

	struct Instance
	{
		uint name;
		uint superName;
		ubyte flags; // InstanceFlags bitmask
		uint protectedNs;
		uint[] interfaces;
		uint iinit;
		TraitsInfo[] traits;
	}

	struct TraitsInfo
	{
		uint name;
		ubyte kindAttr;
		union
		{
			struct _Slot
			{
				uint slotId;
				uint typeName;
				uint vindex;
				Constant vkind;
			} _Slot Slot;
			struct _Class
			{
				uint slotId;
				uint classi;
			} _Class Class;
			struct _Function
			{
				uint slotId;
				uint functioni;
			} _Function Function;
			struct _Method
			{
				uint dispId;
				uint method;
			} _Method Method;
		}
		uint[] metadata;

		TraitKind kind() { return cast(TraitKind)(kindAttr&0xF); }
		void kind(TraitKind value) { kindAttr = (kindAttr&0xF0) | value; }

		// TraitAttributes bitmask
		ubyte attr() { return cast(ubyte)(kindAttr >> 4); }
		void attr(ubyte value) { kindAttr = (kindAttr&0xF) | (value<<4); }
	}

	struct Class
	{
		uint cinit;
		TraitsInfo[] traits;
	}

	struct Script
	{
		uint init;
		TraitsInfo[] traits;
	}

	struct MethodBody
	{
		uint method;
		uint maxStack;
		uint localCount;
		uint initScopeDepth;
		uint maxScopeDepth;
		ubyte[] code;
		ExceptionInfo[] exceptions;
		TraitsInfo[] traits;
	}

	struct ExceptionInfo
	{
		uint from, to, target;
		uint excType;
		uint varName;
	}

	static ABCFile read(InputStream stream)
	{
		return (new ABCReader(stream)).abc;
	}
}

enum Constant : ubyte
{
    Void = 0x00,  // not actually interned
    Utf8 = 0x01,
    Decimal = 0x02,
    Integer = 0x03,
    UInteger = 0x04,
    PrivateNamespace = 0x05,
    Double = 0x06,
    QName = 0x07,  // ns::name, const ns, const name
    Namespace = 0x08,
    Multiname = 0x09,    //[ns...]::name, const [ns...], const name
    False = 0x0A,
    True = 0x0B,
    Null = 0x0C,
    QNameA = 0x0D,    // @ns::name, const ns, const name
    MultinameA = 0x0E,// @[ns...]::name, const [ns...], const name
    RTQName = 0x0F,    // ns::name, var ns, const name
    RTQNameA = 0x10,    // @ns::name, var ns, const name
    RTQNameL = 0x11,    // ns::[name], var ns, var name
    RTQNameLA = 0x12, // @ns::[name], var ns, var name
    Namespace_Set = 0x15, // a set of namespaces - used by multiname
    PackageNamespace = 0x16, // a namespace that was derived from a package
    PackageInternalNs = 0x17, // a namespace that had no uri
    ProtectedNamespace = 0x18,
    ExplicitNamespace = 0x19,
    StaticProtectedNs = 0x1A,
    MultinameL = 0x1B,
    MultinameLA = 0x1C,
    TypeName = 0x1D,
}

/* These enumerations are as they are documented in the AVM bytecode specification.
   They are actually a single enumeration (see above), but in some contexts only cert

enum NamespaceKind : ubyte
{
	Namespace = 0x08,
	PackageNamespace = 0x16,
	PackageInternalNs = 0x17,
	ProtectedNamespace = 0x18,
	ExplicitNamespace = 0x19,
	StaticProtectedNs = 0x1A,
	PrivateNs = 0x05
}

enum MultinameKind : ubyte
{
	QName = 0x07,
	QNameA = 0x0D,
	RTQName = 0x0F,
	RTQNameA = 0x10,
	RTQNameL = 0x11,
	RTQNameLA = 0x12,
	Multiname = 0x09,
	MultinameA = 0x0E,
	MultinameL = 0x1B,
	MultinameLA = 0x1C
}

enum ConstantKind : ubyte
{
	Int = 0x03, // integer
	UInt = 0x04, // uinteger
	Double = 0x06, // double
	Utf8 = 0x01, // string
	True = 0x0B, // -
	False = 0x0A, // -
	Null = 0x0C, // -
	Undefined = 0x00, // -
	Namespace = 0x08, // namespace
	PackageNamespace = 0x16, // namespace
	PackageInternalNs = 0x17, // Namespace
	ProtectedNamespace = 0x18, // Namespace
	ExplicitNamespace = 0x19, // Namespace
	StaticProtectedNs = 0x1A, // Namespace
	PrivateNs = 0x05, // namespace	
}
*/

enum MethodFlags : ubyte
{
	NEED_ARGUMENTS = 0x01, // Suggests to the run-time that an “arguments” object (as specified by the ActionScript 3.0 Language Reference) be created. Must not be used together with NEED_REST. See Chapter 3.
	NEED_ACTIVATION = 0x02, // Must be set if this method uses the newactivation opcode.
	NEED_REST = 0x04, // This flag creates an ActionScript 3.0 rest arguments array. Must not be used with NEED_ARGUMENTS. See Chapter 3.
	HAS_OPTIONAL = 0x08, // Must be set if this method has optional parameters and the options field is present in this method_info structure.
	SET_DXNS = 0x40, // Must be set if this method uses the dxns or dxnslate opcodes.
	HAS_PARAM_NAMES = 0x80, // Must be set when the param_names field is present in this method_info structure.	
}

enum InstanceFlags : ubyte
{
	Sealed = 0x01, // The class is sealed: properties can not be dynamically added to instances of the class.
	Final = 0x02, // The class is final: it cannot be a base class for any other class.
	Interface = 0x04, // The class is an interface.
	ProtectedNs = 0x08, // The class uses its protected namespace and the protectedNs field is present in the interface_info structure.
}

enum TraitKind : ubyte
{
	Slot = 0,
	Method = 1,
	Getter = 2,
	Setter = 3,
	Class = 4,
	Function = 5,
	Const = 6,
}

enum TraitAttributes : ubyte
{
	Final = 1,
	Override = 2,
	Metadata = 4
}

class ABCReader
{
	InputStream stream;
	ABCFile abc;

	this(InputStream stream)
	{
		this.stream = stream;
		abc = new ABCFile();

		abc.minorVersion = readU16();
		abc.majorVersion = readU16();

		static uint atLeastOne(uint n) { return n ? n : 1; }

		abc.ints.length = atLeastOne(readU30());
		foreach (ref value; abc.ints[1..$])
			value = readS32();

		abc.uints.length = atLeastOne(readU30());
		foreach (ref value; abc.uints[1..$])
			value = readU32();
		
		abc.doubles.length = atLeastOne(readU30());
		foreach (ref value; abc.doubles[1..$])
			value = readD64();
		
		abc.strings.length = atLeastOne(readU30());
		foreach (ref value; abc.strings[1..$])
			value = readString();
		
		abc.namespaces.length = atLeastOne(readU30());
		foreach (ref value; abc.namespaces[1..$])
			value = readNamespace();
		
		abc.namespaceSets.length = atLeastOne(readU30());
		foreach (ref value; abc.namespaceSets[1..$])
			value = readNamespaceSet();

		abc.multinames.length = atLeastOne(readU30());
		foreach (ref value; abc.multinames[1..$])
			value = readMultiname();

		abc.methods.length = readU30();
		foreach (ref value; abc.methods)

		abc.metadata.length = readU30();
		foreach (ref value; abc.metadata)
			value = readMetadata();

		abc.instances.length = readU30();
		foreach (ref value; abc.instances)
			value = readInstance();

		abc.classes.length = abc.instances.length;
		foreach (ref value; abc.classes)
			value = readClass();

		abc.scripts.length = readU30();
		foreach (ref value; abc.scripts)
			value = readScript();

		abc.bodies.length = readU30();
		foreach (ref value; abc.bodies)
			value = readMethodBody();
	}

final:
	ubyte readU8()
	{
		ubyte r;
		stream.read(r);
		return r;
	}

	ushort readU16()
	{
		return readU8() | readU8() << 8;
	}

	/// Note: may return values larger than 0xFFFFFFFF.
	ulong readU32()
	{
	    ulong result = readU8();
	    if (0==(result & 0x00000080))
	        return result;
	    result = result & 0x0000007f | readU8()<<7;
	    if (0==(result & 0x00004000))
	        return result;
	    result = result & 0x00003fff | readU8()<<14;
	    if (0==(result & 0x00200000))
	        return result;
	    result = result & 0x001fffff | readU8()<<21;
	    if (0==(result & 0x10000000))
	        return result;
	    return   result & 0x0fffffff | readU8()<<28;
	}

	long readS32()
	{
		ulong l = readU32();
		if (l & 0xFFFFFFFF00000000) // preserve unused bits
			return cast(long)l;
		else
			return cast(int)l;
	}

	uint readU30()
	{
		return cast(uint)readU32() & 0x3FFFFFFF;
	}

	double readD64()
	{
		double r;
		static assert(double.sizeof == 8);
		stream.readExact(&r, 8);
		return r;
	}

	string readString()
	{
		string s = new char[readU30()];
		stream.readExact(s.ptr, s.length);
		return s;
	}

	ubyte[] readBytes()
	{
		ubyte[] r = new ubyte[readU30()];
		stream.readExact(r.ptr, r.length);
		return r;
	}

	ABCFile.Namespace readNamespace()
	{
		ABCFile.Namespace r;
		r.kind = cast(Constant)readU8();
		r.name = readU30();
		return r;
	}

	uint[] readNamespaceSet()
	{
		uint[] r;
		r.length = readU30();
		foreach (ref value; r)
			value = readU30();
		return r;
	}

	ABCFile.Multiname readMultiname()
	{
		ABCFile.Multiname r;
		r.kind = cast(Constant)readU8();
		switch (r.kind)
		{
			case Constant.QName:
			case Constant.QNameA:
				r.QName.ns = readU30();
				r.QName.name = readU30();
				break;
			case Constant.RTQName:
			case Constant.RTQNameA:
				r.RTQName.name = readU30();
				break;
			case Constant.RTQNameL:
			case Constant.RTQNameLA:
				break;
			case Constant.Multiname:
			case Constant.MultinameA:
				r.Multiname.name = readU30();
				r.Multiname.nsSet = readU30();
				break;
			case Constant.MultinameL:
			case Constant.MultinameLA:
				r.MultinameL.nsSet = readU30();
				break;
			case Constant.TypeName:
				r.TypeName.name = readU30();
				r.TypeName.params.length = readU30();
				foreach (ref value; r.TypeName.params)
					value = readU30();
				break;
			default:
				throw new Exception("Unknown Multiname kind");
		}
		return r;
	}

	ABCFile.MethodInfo readMethodInfo()
	{
		ABCFile.MethodInfo r;
		r.params.length = readU30();
		r.returnType = readU30();
		foreach (ref value; r.params)
			value = readU30();
		r.name = readU30();
		r.flags = readU8();
		if (r.flags & MethodFlags.HAS_OPTIONAL)
		{
			r.options.length = readU30();
			foreach (ref option; r.options)
				option = readOptionDetail();
		}
		if (r.flags & MethodFlags.HAS_PARAM_NAMES)
		{
			r.paramNames.length = r.params.length;
			foreach (ref value; r.paramNames)
				value = readU30();
		}
		return r;
	}

	ABCFile.OptionDetail readOptionDetail()
	{
		ABCFile.OptionDetail r;
		r.val = readU30();
		r.kind = cast(Constant)readU8();
		return r;
	}

	ABCFile.Metadata readMetadata()
	{
		ABCFile.Metadata r;
		r.name = readU30();
		r.items.length = readU30();
		foreach (ref value; r.items)
		{
			value.key = readU30();
			value.value = readU30();
		}
		return r;
	}

	ABCFile.Instance readInstance()
	{
		ABCFile.Instance r;
		r.name = readU30();
		r.superName = readU30();
		r.flags = readU8();
		if (r.flags & InstanceFlags.ProtectedNs)
			r.protectedNs = readU30();
		r.interfaces.length = readU30();
		foreach (ref value; r.interfaces)
			value = readU30();
		r.iinit = readU30();
		r.traits.length = readU30();
		foreach (i, ref value; r.traits)
			value = readTrait();

		return r;
	}

	ABCFile.TraitsInfo readTrait()
	{
		ABCFile.TraitsInfo r;
		r.name = readU30();
		r.kindAttr = readU8();
		switch (r.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				r.Slot.slotId = readU30();
				r.Slot.typeName = readU30();
				r.Slot.vindex = readU30();
				if (r.Slot.vindex)
					r.Slot.vkind = cast(Constant)readU8();
				break;
			case TraitKind.Class:
				r.Class.slotId = readU30();
				r.Class.classi = readU30();
				break;
			case TraitKind.Function:
				r.Function.slotId = readU30();
				r.Function.functioni = readU30();
				break;
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				r.Method.dispId = readU30();
				r.Method.method = readU30();
				break;
			default:
				throw new Exception("Unknown trait kind");
		}
		if (r.attr & TraitAttributes.Metadata)
		{
			r.metadata.length = readU30();
			foreach (ref value; r.metadata)
				value = readU30();
		}
		return r;
	}

	ABCFile.Class readClass()
	{
		ABCFile.Class r;
		r.cinit = readU30();
		r.traits.length = readU30();
		foreach (ref value; r.traits)
			value = readTrait();
		return r;
	}

	ABCFile.Script readScript()
	{
		ABCFile.Script r;
		r.init = readU30();
		r.traits.length = readU30();
		foreach (ref value; r.traits)
			value = readTrait();
		return r;
	}

	ABCFile.MethodBody readMethodBody()
	{
		ABCFile.MethodBody r;
		r.method = readU30();
		r.maxStack = readU30();
		r.localCount = readU30();
		r.initScopeDepth = readU30();
		r.maxScopeDepth = readU30();
		r.code = readBytes();
		r.exceptions.length = readU30();
		foreach (ref value; r.exceptions)
			value = readExceptionInfo();
		r.traits.length = readU30();
		foreach (ref value; r.traits)
			value = readTrait();
		return r;
	}

	ABCFile.ExceptionInfo readExceptionInfo()
	{
		ABCFile.ExceptionInfo r;
		r.from = readU30();
		r.to = readU30();
		r.target = readU30();
		r.excType = readU30();
		r.varName = readU30();
		return r;
	}
}
