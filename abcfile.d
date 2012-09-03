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

module abcfile;

import std.string : format; // exception formatting
import std.conv;
import std.exception;

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

	enum long NULL_INT = long.max;
	enum ulong NULL_UINT = ulong.max;
	enum double NULL_DOUBLE = double.init; // NaN

	enum ulong MAX_UINT = (1L << 36) - 1;
	enum long MAX_INT = MAX_UINT / 2;
	enum long MIN_INT = -MAX_INT - 1;

	this()
	{
		majorVersion = 46;
		minorVersion = 16;

		ints.length = 1;
		ints[0] = NULL_INT;

		uints.length = 1;
		uints[0] = NULL_UINT;

		doubles.length = 1;
		doubles[0] = NULL_DOUBLE;

		strings.length = 1;
		namespaces.length = 1;
		namespaceSets.length = 1;
		multinames.length = 1;
	}

	struct Namespace
	{
		ASType kind;
		uint name;
	}

	struct Multiname
	{
		ASType kind;
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
		uint[] paramTypes;
		uint returnType;
		uint name;
		ubyte flags; // MethodFlags bitmask
		OptionDetail[] options;
		uint[] paramNames;
	}

	struct OptionDetail
	{
		uint val;
		ASType kind;
	}

	struct Metadata
	{
		uint name;
		uint[] keys, values;
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
				ASType vkind;
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

		@property TraitKind kind() { return cast(TraitKind)(kindAttr&0xF); }
		@property void kind(TraitKind value) { kindAttr = (kindAttr&0xF0) | value; }

		// TraitAttributes bitmask
		@property ubyte attr() { return cast(ubyte)(kindAttr >> 4); }
		@property void attr(ubyte value) { kindAttr = cast(ubyte)((kindAttr&0xF) | (value<<4)); }
	}

	struct Class
	{
		uint cinit;
		TraitsInfo[] traits;
	}

	struct Script
	{
		uint sinit;
		TraitsInfo[] traits;
	}

	struct MethodBody
	{
		uint method;
		uint maxStack;
		uint localCount;
		uint initScopeDepth;
		uint maxScopeDepth;
		Instruction[] instructions;
		ExceptionInfo[] exceptions;
		TraitsInfo[] traits;

		string error;
		ubyte[] rawBytes;
	}

	/// Destination for a jump or exception block boundary
	struct Label
	{
		union
		{
			struct
			{
				uint index; /// instruction index
				int offset; /// signed offset relative to said instruction
			}
			private ptrdiff_t absoluteOffset; /// internal temporary value used during reading and writing
		}
	}

	struct Instruction
	{
		Opcode opcode;
		union Argument
		{
			ubyte ubytev;
			long intv;
			ulong uintv;
			uint index;

			Label jumpTarget;
			Label[] switchTargets;
		}
		Argument[] arguments;
	}

	struct ExceptionInfo
	{
		Label from, to, target;
		uint excType;
		uint varName;
	}

	static ABCFile read(ubyte[] data)
	{
		return (new ABCReader(data)).abc;
	}

	ubyte[] write()
	{
		return (new ABCWriter(this)).buf;
	}
}

enum ASType : ubyte
{
	Void = 0x00,  // not actually interned
	Undefined = Void,
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
	Max
}

string[ASType.Max] ASTypeNames = [
	"Void",
	"Utf8",
	"Decimal",
	"Integer",
	"UInteger",
	"PrivateNamespace",
	"Double",
	"QName",
	"Namespace",
	"Multiname",
	"False",
	"True",
	"Null",
	"QNameA",
	"MultinameA",
	"RTQName",
	"RTQNameA",
	"RTQNameL",
	"RTQNameLA",
	"???",
	"???",
	"Namespace_Set",
	"PackageNamespace",
	"PackageInternalNs",
	"ProtectedNamespace",
	"ExplicitNamespace",
	"StaticProtectedNs",
	"MultinameL",
	"MultinameLA",
	"TypeName",
];

ASType[string] ASTypeByName;

static this()
{
	foreach (t, n; ASTypeNames)
		ASTypeByName[n] = cast(ASType)t;
	ASTypeByName = ASTypeByName.rehash;
}

/* These enumerations are as they are documented in the AVM bytecode specification.
   They are actually a single enumeration (see above), but in some contexts only certain values are valid.

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
	NEED_ARGUMENTS = 0x01, // Suggests to the run-time that an "arguments" object (as specified by the ActionScript 3.0 Language Reference) be created. Must not be used together with NEED_REST. See Chapter 3.
	NEED_ACTIVATION = 0x02, // Must be set if this method uses the newactivation opcode.
	NEED_REST = 0x04, // This flag creates an ActionScript 3.0 rest arguments array. Must not be used with NEED_ARGUMENTS. See Chapter 3.
	HAS_OPTIONAL = 0x08, // Must be set if this method has optional parameters and the options field is present in this method_info structure.
	SET_DXNS = 0x40, // Must be set if this method uses the dxns or dxnslate opcodes.
	HAS_PARAM_NAMES = 0x80, // Must be set when the param_names field is present in this method_info structure.
}

const string[8] MethodFlagNames = ["NEED_ARGUMENTS", "NEED_ACTIVATION", "NEED_REST", "HAS_OPTIONAL", "0x10", "0x20", "SET_DXNS", "HAS_PARAM_NAMES"];

enum InstanceFlags : ubyte
{
	Sealed = 0x01, // The class is sealed: properties can not be dynamically added to instances of the class.
	Final = 0x02, // The class is final: it cannot be a base class for any other class.
	Interface = 0x04, // The class is an interface.
	ProtectedNs = 0x08, // The class uses its protected namespace and the protectedNs field is present in the interface_info structure.
}

const string[8] InstanceFlagNames = ["SEALED", "FINAL", "INTERFACE", "PROTECTEDNS", "0x10", "0x20", "0x40", "0x80"];

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

const string[] TraitKindNames = ["slot", "method", "getter", "setter", "class", "function", "const"];

TraitKind[string] TraitKindByName;

static this()
{
	foreach (t, n; TraitKindNames)
		TraitKindByName[n] = cast(TraitKind)t;
	TraitKindByName = TraitKindByName.rehash;
}

enum TraitAttributes : ubyte
{
	Final = 1,
	Override = 2,
	Metadata = 4
}

const string[4] TraitAttributeNames = ["FINAL", "OVERRIDE", "METADATA", "0x08"];

enum Opcode : ubyte
{
	OP_bkpt = 0x01,
	OP_nop = 0x02,
	OP_throw = 0x03,
	OP_getsuper = 0x04,
	OP_setsuper = 0x05,
	OP_dxns = 0x06,
	OP_dxnslate = 0x07,
	OP_kill = 0x08,
	OP_label = 0x09,
	OP_ifnlt = 0x0C,
	OP_ifnle = 0x0D,
	OP_ifngt = 0x0E,
	OP_ifnge = 0x0F,
	OP_jump = 0x10,
	OP_iftrue = 0x11,
	OP_iffalse = 0x12,
	OP_ifeq = 0x13,
	OP_ifne = 0x14,
	OP_iflt = 0x15,
	OP_ifle = 0x16,
	OP_ifgt = 0x17,
	OP_ifge = 0x18,
	OP_ifstricteq = 0x19,
	OP_ifstrictne = 0x1A,
	OP_lookupswitch = 0x1B,
	OP_pushwith = 0x1C,
	OP_popscope = 0x1D,
	OP_nextname = 0x1E,
	OP_hasnext = 0x1F,
	OP_pushnull = 0x20,
	OP_pushundefined = 0x21,
	OP_pushuninitialized = 0x22,
	OP_nextvalue = 0x23,
	OP_pushbyte = 0x24,
	OP_pushshort = 0x25,
	OP_pushtrue = 0x26,
	OP_pushfalse = 0x27,
	OP_pushnan = 0x28,
	OP_pop = 0x29,
	OP_dup = 0x2A,
	OP_swap = 0x2B,
	OP_pushstring = 0x2C,
	OP_pushint = 0x2D,
	OP_pushuint = 0x2E,
	OP_pushdouble = 0x2F,
	OP_pushscope = 0x30,
	OP_pushnamespace = 0x31,
	OP_hasnext2 = 0x32,
	OP_pushdecimal = 0x33,
	OP_pushdnan = 0x34,
	OP_li8 = 0x35,
	OP_li16 = 0x36,
	OP_li32 = 0x37,
	OP_lf32 = 0x38,
	OP_lf64 = 0x39,
	OP_si8 = 0x3A,
	OP_si16 = 0x3B,
	OP_si32 = 0x3C,
	OP_sf32 = 0x3D,
	OP_sf64 = 0x3E,
	OP_newfunction = 0x40,
	OP_call = 0x41,
	OP_construct = 0x42,
	OP_callmethod = 0x43,
	OP_callstatic = 0x44,
	OP_callsuper = 0x45,
	OP_callproperty = 0x46,
	OP_returnvoid = 0x47,
	OP_returnvalue = 0x48,
	OP_constructsuper = 0x49,
	OP_constructprop = 0x4A,
	OP_callsuperid = 0x4B,
	OP_callproplex = 0x4C,
	OP_callinterface = 0x4D,
	OP_callsupervoid = 0x4E,
	OP_callpropvoid = 0x4F,
	OP_sxi1 = 0x50,
	OP_sxi8 = 0x51,
	OP_sxi16 = 0x52,
	OP_applytype = 0x53,
	OP_newobject = 0x55,
	OP_newarray = 0x56,
	OP_newactivation = 0x57,
	OP_newclass = 0x58,
	OP_getdescendants = 0x59,
	OP_newcatch = 0x5A,
	OP_deldescendants = 0x5B,
	OP_findpropstrict = 0x5D,
	OP_findproperty = 0x5E,
	OP_finddef = 0x5F,
	OP_getlex = 0x60,
	OP_setproperty = 0x61,
	OP_getlocal = 0x62,
	OP_setlocal = 0x63,
	OP_getglobalscope = 0x64,
	OP_getscopeobject = 0x65,
	OP_getproperty = 0x66,
	OP_getpropertylate = 0x67,
	OP_initproperty = 0x68,
	OP_setpropertylate = 0x69,
	OP_deleteproperty = 0x6A,
	OP_deletepropertylate = 0x6B,
	OP_getslot = 0x6C,
	OP_setslot = 0x6D,
	OP_getglobalslot = 0x6E,
	OP_setglobalslot = 0x6F,
	OP_convert_s = 0x70,
	OP_esc_xelem = 0x71,
	OP_esc_xattr = 0x72,
	OP_convert_i = 0x73,
	OP_convert_u = 0x74,
	OP_convert_d = 0x75,
	OP_convert_b = 0x76,
	OP_convert_o = 0x77,
	OP_checkfilter = 0x78,
	OP_convert_m = 0x79,
	OP_convert_m_p = 0x7A,
	OP_coerce = 0x80,
	OP_coerce_b = 0x81,
	OP_coerce_a = 0x82,
	OP_coerce_i = 0x83,
	OP_coerce_d = 0x84,
	OP_coerce_s = 0x85,
	OP_astype = 0x86,
	OP_astypelate = 0x87,
	OP_coerce_u = 0x88,
	OP_coerce_o = 0x89,
	OP_negate_p = 0x8F,
	OP_negate = 0x90,
	OP_increment = 0x91,
	OP_inclocal = 0x92,
	OP_decrement = 0x93,
	OP_declocal = 0x94,
	OP_typeof = 0x95,
	OP_not = 0x96,
	OP_bitnot = 0x97,
	OP_concat = 0x9A,
	OP_add_d = 0x9B,
	OP_increment_p = 0x9C,
	OP_inclocal_p = 0x9D,
	OP_decrement_p = 0x9E,
	OP_declocal_p = 0x9F,
	OP_add = 0xA0,
	OP_subtract = 0xA1,
	OP_multiply = 0xA2,
	OP_divide = 0xA3,
	OP_modulo = 0xA4,
	OP_lshift = 0xA5,
	OP_rshift = 0xA6,
	OP_urshift = 0xA7,
	OP_bitand = 0xA8,
	OP_bitor = 0xA9,
	OP_bitxor = 0xAA,
	OP_equals = 0xAB,
	OP_strictequals = 0xAC,
	OP_lessthan = 0xAD,
	OP_lessequals = 0xAE,
	OP_greaterthan = 0xAF,
	OP_greaterequals = 0xB0,
	OP_instanceof = 0xB1,
	OP_istype = 0xB2,
	OP_istypelate = 0xB3,
	OP_in = 0xB4,
	OP_add_p = 0xB5,
	OP_subtract_p = 0xB6,
	OP_multiply_p = 0xB7,
	OP_divide_p = 0xB8,
	OP_modulo_p = 0xB9,
	OP_increment_i = 0xC0,
	OP_decrement_i = 0xC1,
	OP_inclocal_i = 0xC2,
	OP_declocal_i = 0xC3,
	OP_negate_i = 0xC4,
	OP_add_i = 0xC5,
	OP_subtract_i = 0xC6,
	OP_multiply_i = 0xC7,
	OP_getlocal0 = 0xD0,
	OP_getlocal1 = 0xD1,
	OP_getlocal2 = 0xD2,
	OP_getlocal3 = 0xD3,
	OP_setlocal0 = 0xD4,
	OP_setlocal1 = 0xD5,
	OP_setlocal2 = 0xD6,
	OP_setlocal3 = 0xD7,
	OP_debug = 0xEF,
	OP_debugline = 0xF0,
	OP_debugfile = 0xF1,
	OP_bkptline = 0xF2,
	OP_timestamp = 0xF3,
}

enum OpcodeArgumentType
{
	Unknown,

	UByteLiteral,
	IntLiteral,
	UIntLiteral,

	Int,
	UInt,
	Double,
	String,
	Namespace,
	Multiname,
	Class,
	Method,

	JumpTarget,
	SwitchDefaultTarget,
	SwitchTargets,
}

struct OpcodeInfo
{
	string name;
	OpcodeArgumentType[] argumentTypes;
}

const OpcodeInfo[256] opcodeInfo = [
	/* 0x00 */		{"0x00",				[OpcodeArgumentType.Unknown]},
	/* 0x01 */		{"bkpt",				[OpcodeArgumentType.Unknown]},
	/* 0x02 */		{"nop",					[]},
	/* 0x03 */		{"throw",				[]},
	/* 0x04 */		{"getsuper",			[OpcodeArgumentType.Multiname]},
	/* 0x05 */		{"setsuper",			[OpcodeArgumentType.Multiname]},
	/* 0x06 */		{"dxns",				[OpcodeArgumentType.String]},
	/* 0x07 */		{"dxnslate",			[]},
	/* 0x08 */		{"kill",				[OpcodeArgumentType.UIntLiteral]},
	/* 0x09 */		{"label",				[]},
	/* 0x0A */		{"0x0A",				[OpcodeArgumentType.Unknown]},
	/* 0x0B */		{"0x0B",				[OpcodeArgumentType.Unknown]},
	/* 0x0C */		{"ifnlt",				[OpcodeArgumentType.JumpTarget]},
	/* 0x0D */		{"ifnle",				[OpcodeArgumentType.JumpTarget]},
	/* 0x0E */		{"ifngt",				[OpcodeArgumentType.JumpTarget]},
	/* 0x0F */		{"ifnge",				[OpcodeArgumentType.JumpTarget]},
	/* 0x10 */		{"jump",				[OpcodeArgumentType.JumpTarget]},
	/* 0x11 */		{"iftrue",				[OpcodeArgumentType.JumpTarget]},
	/* 0x12 */		{"iffalse",				[OpcodeArgumentType.JumpTarget]},
	/* 0x13 */		{"ifeq",				[OpcodeArgumentType.JumpTarget]},
	/* 0x14 */		{"ifne",				[OpcodeArgumentType.JumpTarget]},
	/* 0x15 */		{"iflt",				[OpcodeArgumentType.JumpTarget]},
	/* 0x16 */		{"ifle",				[OpcodeArgumentType.JumpTarget]},
	/* 0x17 */		{"ifgt",				[OpcodeArgumentType.JumpTarget]},
	/* 0x18 */		{"ifge",				[OpcodeArgumentType.JumpTarget]},
	/* 0x19 */		{"ifstricteq",			[OpcodeArgumentType.JumpTarget]},
	/* 0x1A */		{"ifstrictne",			[OpcodeArgumentType.JumpTarget]},
	/* 0x1B */		{"lookupswitch",		[OpcodeArgumentType.SwitchDefaultTarget, OpcodeArgumentType.SwitchTargets]},
	/* 0x1C */		{"pushwith",			[]},
	/* 0x1D */		{"popscope",			[]},
	/* 0x1E */		{"nextname",			[]},
	/* 0x1F */		{"hasnext",				[]},
	/* 0x20 */		{"pushnull",			[]},
	/* 0x21 */		{"pushundefined",		[]},
	/* 0x22 */		{"pushuninitialized",	[OpcodeArgumentType.Unknown]},
	/* 0x23 */		{"nextvalue",			[]},
	/* 0x24 */		{"pushbyte",			[OpcodeArgumentType.UByteLiteral]},
	/* 0x25 */		{"pushshort",			[OpcodeArgumentType.IntLiteral]},
	/* 0x26 */		{"pushtrue",			[]},
	/* 0x27 */		{"pushfalse",			[]},
	/* 0x28 */		{"pushnan",				[]},
	/* 0x29 */		{"pop",					[]},
	/* 0x2A */		{"dup",					[]},
	/* 0x2B */		{"swap",				[]},
	/* 0x2C */		{"pushstring",			[OpcodeArgumentType.String]},
	/* 0x2D */		{"pushint",				[OpcodeArgumentType.Int]},
	/* 0x2E */		{"pushuint",			[OpcodeArgumentType.UInt]},
	/* 0x2F */		{"pushdouble",			[OpcodeArgumentType.Double]},
	/* 0x30 */		{"pushscope",			[]},
	/* 0x31 */		{"pushnamespace",		[OpcodeArgumentType.Namespace]},
	/* 0x32 */		{"hasnext2",			[OpcodeArgumentType.UIntLiteral, OpcodeArgumentType.UIntLiteral]},
	/* 0x33 */		{"pushdecimal",			[OpcodeArgumentType.Unknown]},
	/* 0x34 */		{"pushdnan",			[OpcodeArgumentType.Unknown]},
	/* 0x35 */		{"li8",					[]},
	/* 0x36 */		{"li16",				[]},
	/* 0x37 */		{"li32",				[]},
	/* 0x38 */		{"lf32",				[]},
	/* 0x39 */		{"lf64",				[]},
	/* 0x3A */		{"si8",					[]},
	/* 0x3B */		{"si16",				[]},
	/* 0x3C */		{"si32",				[]},
	/* 0x3D */		{"sf32",				[]},
	/* 0x3E */		{"sf64",				[]},
	/* 0x3F */		{"0x3F",				[OpcodeArgumentType.Unknown]},
	/* 0x40 */		{"newfunction",			[OpcodeArgumentType.Method]},
	/* 0x41 */		{"call",				[OpcodeArgumentType.UIntLiteral]},
	/* 0x42 */		{"construct",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x43 */		{"callmethod",			[OpcodeArgumentType.UIntLiteral, OpcodeArgumentType.UIntLiteral]},
	/* 0x44 */		{"callstatic",			[OpcodeArgumentType.Method, OpcodeArgumentType.UIntLiteral]},
	/* 0x45 */		{"callsuper",			[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x46 */		{"callproperty",		[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x47 */		{"returnvoid",			[]},
	/* 0x48 */		{"returnvalue",			[]},
	/* 0x49 */		{"constructsuper",		[OpcodeArgumentType.UIntLiteral]},
	/* 0x4A */		{"constructprop",		[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x4B */		{"callsuperid",			[OpcodeArgumentType.Unknown]},
	/* 0x4C */		{"callproplex",			[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x4D */		{"callinterface",		[OpcodeArgumentType.Unknown]},
	/* 0x4E */		{"callsupervoid",		[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x4F */		{"callpropvoid",		[OpcodeArgumentType.Multiname, OpcodeArgumentType.UIntLiteral]},
	/* 0x50 */		{"sxi1",				[]},
	/* 0x51 */		{"sxi8",				[]},
	/* 0x52 */		{"sxi16",				[]},
	/* 0x53 */		{"applytype",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x54 */		{"0x54",				[OpcodeArgumentType.Unknown]},
	/* 0x55 */		{"newobject",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x56 */		{"newarray",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x57 */		{"newactivation",		[]},
	/* 0x58 */		{"newclass",			[OpcodeArgumentType.Class]},
	/* 0x59 */		{"getdescendants",		[OpcodeArgumentType.Multiname]},
	/* 0x5A */		{"newcatch",			[OpcodeArgumentType.UIntLiteral]}, // ExceptionInfo index
	/* 0x5B */		{"deldescendants",		[OpcodeArgumentType.Unknown]},
	/* 0x5C */		{"0x5C",				[OpcodeArgumentType.Unknown]},
	/* 0x5D */		{"findpropstrict",		[OpcodeArgumentType.Multiname]},
	/* 0x5E */		{"findproperty",		[OpcodeArgumentType.Multiname]},
	/* 0x5F */		{"finddef",				[OpcodeArgumentType.Unknown]},
	/* 0x60 */		{"getlex",				[OpcodeArgumentType.Multiname]},
	/* 0x61 */		{"setproperty",			[OpcodeArgumentType.Multiname]},
	/* 0x62 */		{"getlocal",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x63 */		{"setlocal",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x64 */		{"getglobalscope",		[]},
	/* 0x65 */		{"getscopeobject",		[OpcodeArgumentType.UByteLiteral]},
	/* 0x66 */		{"getproperty",			[OpcodeArgumentType.Multiname]},
	/* 0x67 */		{"getpropertylate",		[OpcodeArgumentType.Unknown]},
	/* 0x68 */		{"initproperty",		[OpcodeArgumentType.Multiname]},
	/* 0x69 */		{"setpropertylate",		[OpcodeArgumentType.Unknown]},
	/* 0x6A */		{"deleteproperty",		[OpcodeArgumentType.Multiname]},
	/* 0x6B */		{"deletepropertylate",	[OpcodeArgumentType.Unknown]},
	/* 0x6C */		{"getslot",				[OpcodeArgumentType.UIntLiteral]},
	/* 0x6D */		{"setslot",				[OpcodeArgumentType.UIntLiteral]},
	/* 0x6E */		{"getglobalslot",		[OpcodeArgumentType.UIntLiteral]},
	/* 0x6F */		{"setglobalslot",		[OpcodeArgumentType.UIntLiteral]},
	/* 0x70 */		{"convert_s",			[]},
	/* 0x71 */		{"esc_xelem",			[]},
	/* 0x72 */		{"esc_xattr",			[]},
	/* 0x73 */		{"convert_i",			[]},
	/* 0x74 */		{"convert_u",			[]},
	/* 0x75 */		{"convert_d",			[]},
	/* 0x76 */		{"convert_b",			[]},
	/* 0x77 */		{"convert_o",			[]},
	/* 0x78 */		{"checkfilter",			[]},
	/* 0x79 */		{"convert_m",			[OpcodeArgumentType.Unknown]},
	/* 0x7A */		{"convert_m_p",			[OpcodeArgumentType.Unknown]},
	/* 0x7B */		{"0x7B",				[OpcodeArgumentType.Unknown]},
	/* 0x7C */		{"0x7C",				[OpcodeArgumentType.Unknown]},
	/* 0x7D */		{"0x7D",				[OpcodeArgumentType.Unknown]},
	/* 0x7E */		{"0x7E",				[OpcodeArgumentType.Unknown]},
	/* 0x7F */		{"0x7F",				[OpcodeArgumentType.Unknown]},
	/* 0x80 */		{"coerce",				[OpcodeArgumentType.Multiname]},
	/* 0x81 */		{"coerce_b",			[]},
	/* 0x82 */		{"coerce_a",			[]},
	/* 0x83 */		{"coerce_i",			[]},
	/* 0x84 */		{"coerce_d",			[]},
	/* 0x85 */		{"coerce_s",			[]},
	/* 0x86 */		{"astype",				[OpcodeArgumentType.Multiname]},
	/* 0x87 */		{"astypelate",			[]},
	/* 0x88 */		{"coerce_u",			[OpcodeArgumentType.Unknown]},
	/* 0x89 */		{"coerce_o",			[OpcodeArgumentType.Unknown]},
	/* 0x8A */		{"0x8A",				[OpcodeArgumentType.Unknown]},
	/* 0x8B */		{"0x8B",				[OpcodeArgumentType.Unknown]},
	/* 0x8C */		{"0x8C",				[OpcodeArgumentType.Unknown]},
	/* 0x8D */		{"0x8D",				[OpcodeArgumentType.Unknown]},
	/* 0x8E */		{"0x8E",				[OpcodeArgumentType.Unknown]},
	/* 0x8F */		{"negate_p",			[OpcodeArgumentType.Unknown]},
	/* 0x90 */		{"negate",				[]},
	/* 0x91 */		{"increment",			[]},
	/* 0x92 */		{"inclocal",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x93 */		{"decrement",			[]},
	/* 0x94 */		{"declocal",			[OpcodeArgumentType.UIntLiteral]},
	/* 0x95 */		{"typeof",				[]},
	/* 0x96 */		{"not",					[]},
	/* 0x97 */		{"bitnot",				[]},
	/* 0x98 */		{"0x98",				[OpcodeArgumentType.Unknown]},
	/* 0x99 */		{"0x99",				[OpcodeArgumentType.Unknown]},
	/* 0x9A */		{"concat",				[OpcodeArgumentType.Unknown]},
	/* 0x9B */		{"add_d",				[OpcodeArgumentType.Unknown]},
	/* 0x9C */		{"increment_p",			[OpcodeArgumentType.Unknown]},
	/* 0x9D */		{"inclocal_p",			[OpcodeArgumentType.Unknown]},
	/* 0x9E */		{"decrement_p",			[OpcodeArgumentType.Unknown]},
	/* 0x9F */		{"declocal_p",			[OpcodeArgumentType.Unknown]},
	/* 0xA0 */		{"add",					[]},
	/* 0xA1 */		{"subtract",			[]},
	/* 0xA2 */		{"multiply",			[]},
	/* 0xA3 */		{"divide",				[]},
	/* 0xA4 */		{"modulo",				[]},
	/* 0xA5 */		{"lshift",				[]},
	/* 0xA6 */		{"rshift",				[]},
	/* 0xA7 */		{"urshift",				[]},
	/* 0xA8 */		{"bitand",				[]},
	/* 0xA9 */		{"bitor",				[]},
	/* 0xAA */		{"bitxor",				[]},
	/* 0xAB */		{"equals",				[]},
	/* 0xAC */		{"strictequals",		[]},
	/* 0xAD */		{"lessthan",			[]},
	/* 0xAE */		{"lessequals",			[]},
	/* 0xAF */		{"greaterthan",			[]},
	/* 0xB0 */		{"greaterequals",		[]},
	/* 0xB1 */		{"instanceof",			[]},
	/* 0xB2 */		{"istype",				[OpcodeArgumentType.Multiname]},
	/* 0xB3 */		{"istypelate",			[]},
	/* 0xB4 */		{"in",					[]},
	/* 0xB5 */		{"add_p",				[OpcodeArgumentType.Unknown]},
	/* 0xB6 */		{"subtract_p",			[OpcodeArgumentType.Unknown]},
	/* 0xB7 */		{"multiply_p",			[OpcodeArgumentType.Unknown]},
	/* 0xB8 */		{"divide_p",			[OpcodeArgumentType.Unknown]},
	/* 0xB9 */		{"modulo_p",			[OpcodeArgumentType.Unknown]},
	/* 0xBA */		{"0xBA",				[OpcodeArgumentType.Unknown]},
	/* 0xBB */		{"0xBB",				[OpcodeArgumentType.Unknown]},
	/* 0xBC */		{"0xBC",				[OpcodeArgumentType.Unknown]},
	/* 0xBD */		{"0xBD",				[OpcodeArgumentType.Unknown]},
	/* 0xBE */		{"0xBE",				[OpcodeArgumentType.Unknown]},
	/* 0xBF */		{"0xBF",				[OpcodeArgumentType.Unknown]},
	/* 0xC0 */		{"increment_i",			[]},
	/* 0xC1 */		{"decrement_i",			[]},
	/* 0xC2 */		{"inclocal_i",			[OpcodeArgumentType.UIntLiteral]},
	/* 0xC3 */		{"declocal_i",			[OpcodeArgumentType.UIntLiteral]},
	/* 0xC4 */		{"negate_i",			[]},
	/* 0xC5 */		{"add_i",				[]},
	/* 0xC6 */		{"subtract_i",			[]},
	/* 0xC7 */		{"multiply_i",			[]},
	/* 0xC8 */		{"0xC8",				[OpcodeArgumentType.Unknown]},
	/* 0xC9 */		{"0xC9",				[OpcodeArgumentType.Unknown]},
	/* 0xCA */		{"0xCA",				[OpcodeArgumentType.Unknown]},
	/* 0xCB */		{"0xCB",				[OpcodeArgumentType.Unknown]},
	/* 0xCC */		{"0xCC",				[OpcodeArgumentType.Unknown]},
	/* 0xCD */		{"0xCD",				[OpcodeArgumentType.Unknown]},
	/* 0xCE */		{"0xCE",				[OpcodeArgumentType.Unknown]},
	/* 0xCF */		{"0xCF",				[OpcodeArgumentType.Unknown]},
	/* 0xD0 */		{"getlocal0",			[]},
	/* 0xD1 */		{"getlocal1",			[]},
	/* 0xD2 */		{"getlocal2",			[]},
	/* 0xD3 */		{"getlocal3",			[]},
	/* 0xD4 */		{"setlocal0",			[]},
	/* 0xD5 */		{"setlocal1",			[]},
	/* 0xD6 */		{"setlocal2",			[]},
	/* 0xD7 */		{"setlocal3",			[]},
	/* 0xD8 */		{"0xD8",				[OpcodeArgumentType.Unknown]},
	/* 0xD9 */		{"0xD9",				[OpcodeArgumentType.Unknown]},
	/* 0xDA */		{"0xDA",				[OpcodeArgumentType.Unknown]},
	/* 0xDB */		{"0xDB",				[OpcodeArgumentType.Unknown]},
	/* 0xDC */		{"0xDC",				[OpcodeArgumentType.Unknown]},
	/* 0xDD */		{"0xDD",				[OpcodeArgumentType.Unknown]},
	/* 0xDE */		{"0xDE",				[OpcodeArgumentType.Unknown]},
	/* 0xDF */		{"0xDF",				[OpcodeArgumentType.Unknown]},
	/* 0xE0 */		{"0xE0",				[OpcodeArgumentType.Unknown]},
	/* 0xE1 */		{"0xE1",				[OpcodeArgumentType.Unknown]},
	/* 0xE2 */		{"0xE2",				[OpcodeArgumentType.Unknown]},
	/* 0xE3 */		{"0xE3",				[OpcodeArgumentType.Unknown]},
	/* 0xE4 */		{"0xE4",				[OpcodeArgumentType.Unknown]},
	/* 0xE5 */		{"0xE5",				[OpcodeArgumentType.Unknown]},
	/* 0xE6 */		{"0xE6",				[OpcodeArgumentType.Unknown]},
	/* 0xE7 */		{"0xE7",				[OpcodeArgumentType.Unknown]},
	/* 0xE8 */		{"0xE8",				[OpcodeArgumentType.Unknown]},
	/* 0xE9 */		{"0xE9",				[OpcodeArgumentType.Unknown]},
	/* 0xEA */		{"0xEA",				[OpcodeArgumentType.Unknown]},
	/* 0xEB */		{"0xEB",				[OpcodeArgumentType.Unknown]},
	/* 0xEC */		{"0xEC",				[OpcodeArgumentType.Unknown]},
	/* 0xED */		{"0xED",				[OpcodeArgumentType.Unknown]},
	/* 0xEE */		{"0xEE",				[OpcodeArgumentType.Unknown]},
	/* 0xEF */		{"debug",				[OpcodeArgumentType.UByteLiteral, OpcodeArgumentType.String, OpcodeArgumentType.UByteLiteral, OpcodeArgumentType.UIntLiteral]},
	/* 0xF0 */		{"debugline",			[OpcodeArgumentType.UIntLiteral]},
	/* 0xF1 */		{"debugfile",			[OpcodeArgumentType.String]},
	/* 0xF2 */		{"bkptline",			[OpcodeArgumentType.Unknown]},
	/* 0xF3 */		{"timestamp",			[OpcodeArgumentType.Unknown]},
	/* 0xF4 */		{"0xF4",				[OpcodeArgumentType.Unknown]},
	/* 0xF5 */		{"0xF5",				[OpcodeArgumentType.Unknown]},
	/* 0xF6 */		{"0xF6",				[OpcodeArgumentType.Unknown]},
	/* 0xF7 */		{"0xF7",				[OpcodeArgumentType.Unknown]},
	/* 0xF8 */		{"0xF8",				[OpcodeArgumentType.Unknown]},
	/* 0xF9 */		{"0xF9",				[OpcodeArgumentType.Unknown]},
	/* 0xFA */		{"0xFA",				[OpcodeArgumentType.Unknown]},
	/* 0xFB */		{"0xFB",				[OpcodeArgumentType.Unknown]},
	/* 0xFC */		{"0xFC",				[OpcodeArgumentType.Unknown]},
	/* 0xFD */		{"0xFD",				[OpcodeArgumentType.Unknown]},
	/* 0xFE */		{"0xFE",				[OpcodeArgumentType.Unknown]},
	/* 0xFF */		{"0xFF",				[OpcodeArgumentType.Unknown]},
];

Opcode[string] OpcodeByName;

static this()
{
	foreach (o, ref i; opcodeInfo)
		OpcodeByName[i.name] = cast(Opcode)o;
	OpcodeByName = OpcodeByName.rehash;
}

private final class ABCReader
{
	ubyte[] buf;
	size_t pos;
	ABCFile abc;

	this(ubyte[] buf)
	{
		try
		{
			this.buf = buf;
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
				value = readMethodInfo();

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
		catch (Exception e)
			throw new Exception(format("Error at %d (0x%X):", pos, pos), e);
	}

	ubyte readU8()
	{
		enforce(pos < buf.length, "End of file reached");
		return buf[pos++];
	}

	ushort readU16()
	{
		return readU8() | readU8() << 8;
	}

	int readS24()
	{
		return readU8() | readU8() << 8 | cast(int)(readU8() << 24) >> 8;
	}

	/// Note: may return values larger than 0xFFFFFFFF.
	ulong readU32()
	out(result)
	{
		assert(result <= ABCFile.MAX_UINT);
	}
	body
	{
		ulong next() { return readU8(); } // force ulong

		ulong result = next();
		if (0==(result & 0x00000080))
			return result;
		result = result & 0x0000007f | next()<<7;
		if (0==(result & 0x00004000))
			return result;
		result = result & 0x00003fff | next()<<14;
		if (0==(result & 0x00200000))
			return result;
		result = result & 0x001fffff | next()<<21;
		if (0==(result & 0x10000000))
			return result;
		return   result & 0x0fffffff | next()<<28;
	}

	long readS32()
	out(result)
	{
		assert(result >= ABCFile.MIN_INT && result <= ABCFile.MAX_INT);
	}
	body
	{
		auto l = readU32();
		if (l & 0xFFFFFFFF_00000000) // preserve unused bits
			return l | 0xFFFFFFF0_00000000;
		else
			return cast(int)l;
	}

	uint readU30()
	{
		return cast(uint)readU32() & 0x3FFFFFFF;
	}

	void readExact(void* ptr, size_t len)
	{
		enforce(pos+len <= buf.length, "End of file reached");
		(cast(ubyte*)ptr)[0..len] = buf[pos..pos+len];
		pos += len;
	}

	double readD64()
	{
		double r;
		static assert(double.sizeof == 8);
		readExact(&r, 8);
		return r;
	}

	string readString()
	{
		char[] buf = new char[readU30()];
		readExact(buf.ptr, buf.length);
		string s = assumeUnique(buf);
		if (s.length == 0)
			s = ""; // not null!
		return s;
	}

	ubyte[] readBytes()
	{
		ubyte[] r = new ubyte[readU30()];
		readExact(r.ptr, r.length);
		return r;
	}

	ABCFile.Namespace readNamespace()
	{
		ABCFile.Namespace r;
		r.kind = cast(ASType)readU8();
		r.name = readU30();
		return r;
	}

	uint[] readNamespaceSet()
	{
		uint[] r;
		r.length = readU30();
		foreach (ref value; r)
			value = readU30();
		if (r.length == 0)
		{
			r.length = 1;
			r.length = 0;
			assert (r !is null); // empty, but not null
		}
		return r;
	}

	ABCFile.Multiname readMultiname()
	{
		ABCFile.Multiname r;
		r.kind = cast(ASType)readU8();
		switch (r.kind)
		{
			case ASType.QName:
			case ASType.QNameA:
				r.QName.ns = readU30();
				r.QName.name = readU30();
				break;
			case ASType.RTQName:
			case ASType.RTQNameA:
				r.RTQName.name = readU30();
				break;
			case ASType.RTQNameL:
			case ASType.RTQNameLA:
				break;
			case ASType.Multiname:
			case ASType.MultinameA:
				r.Multiname.name = readU30();
				r.Multiname.nsSet = readU30();
				break;
			case ASType.MultinameL:
			case ASType.MultinameLA:
				r.MultinameL.nsSet = readU30();
				break;
			case ASType.TypeName:
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
		r.paramTypes.length = readU30();
		r.returnType = readU30();
		foreach (ref value; r.paramTypes)
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
			r.paramNames.length = r.paramTypes.length;
			foreach (ref value; r.paramNames)
				value = readU30();
		}
		return r;
	}

	ABCFile.OptionDetail readOptionDetail()
	{
		ABCFile.OptionDetail r;
		r.val = readU30();
		r.kind = cast(ASType)readU8();
		return r;
	}

	ABCFile.Metadata readMetadata()
	{
		ABCFile.Metadata r;
		r.name = readU30();
		r.keys.length = r.values.length = readU30();
		foreach (ref key; r.keys)
			key = readU30();
		foreach (ref value; r.values)
			value = readU30();
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
		foreach (ref value; r.traits)
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
					r.Slot.vkind = cast(ASType)readU8();
				else
					r.Slot.vkind = ASType.Void;
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
		r.sinit = readU30();
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
		r.instructions = null;

		size_t len = readU30();
		auto instructionAtOffset = new uint[len];
		r.rawBytes = buf[pos..pos+len];

		void translateLabel(ref ABCFile.Label label)
		{
			auto absoluteOffset = label.absoluteOffset;
			auto instructionOffset = absoluteOffset;
			while (true)
			{
				if (instructionOffset >= len)
				{
					label.index = to!uint(r.instructions.length);
					instructionOffset = len;
					break;
				}
				if (instructionOffset <= 0)
				{
					label.index = 0;
					instructionOffset = 0;
					break;
				}
				if (instructionAtOffset[instructionOffset] != uint.max)
				{
					label.index = instructionAtOffset[instructionOffset];
					break;
				}
				instructionOffset--;
			}
			label.offset = to!int(absoluteOffset-instructionOffset);
		}

		size_t start = pos;
		size_t end = pos + len;

		@property size_t offset() { return pos - start; }

		try
		{
			instructionAtOffset[] = uint.max;
			size_t[] instructionOffsets;
			while (pos < end)
			{
				auto instructionOffset = offset;
				scope(failure) pos = start + instructionOffset;
				instructionAtOffset[instructionOffset] = to!uint(r.instructions.length);
				ABCFile.Instruction instruction;
				instruction.opcode = cast(Opcode)readU8();
				instruction.arguments.length = opcodeInfo[instruction.opcode].argumentTypes.length;
				foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
					final switch (type)
					{
						case OpcodeArgumentType.Unknown:
							throw new Exception("Don't know how to decode OP_" ~ opcodeInfo[instruction.opcode].name);

						case OpcodeArgumentType.UByteLiteral:
							instruction.arguments[i].ubytev = readU8();
							break;
						case OpcodeArgumentType.IntLiteral:
							instruction.arguments[i].intv = readS32();
							break;
						case OpcodeArgumentType.UIntLiteral:
							instruction.arguments[i].uintv = readU32();
							break;

						case OpcodeArgumentType.Int:
						case OpcodeArgumentType.UInt:
						case OpcodeArgumentType.Double:
						case OpcodeArgumentType.String:
						case OpcodeArgumentType.Namespace:
						case OpcodeArgumentType.Multiname:
						case OpcodeArgumentType.Class:
						case OpcodeArgumentType.Method:
							instruction.arguments[i].index = readU30();
							break;

						case OpcodeArgumentType.JumpTarget:
							int delta = readS24();
							instruction.arguments[i].jumpTarget.absoluteOffset = offset + delta;
							break;

						case OpcodeArgumentType.SwitchDefaultTarget:
							instruction.arguments[i].jumpTarget.absoluteOffset = instructionOffset + readS24();
							break;

						case OpcodeArgumentType.SwitchTargets:
							instruction.arguments[i].switchTargets.length = readU30()+1;
							foreach (ref label; instruction.arguments[i].switchTargets)
								label.absoluteOffset = instructionOffset + readS24();
							break;
					}
				r.instructions ~= instruction;
				instructionOffsets ~= instructionOffset;
			}

			if (pos > end)
				throw new Exception("Out-of-bounds code read error");

			// convert jump target offsets to instruction indices
			foreach (ii, ref instruction; r.instructions)
				foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
					switch (type)
					{
						case OpcodeArgumentType.JumpTarget:
						case OpcodeArgumentType.SwitchDefaultTarget:
							translateLabel(instruction.arguments[i].jumpTarget);
							break;
						case OpcodeArgumentType.SwitchTargets:
							foreach (ref x; instruction.arguments[i].switchTargets)
								translateLabel(x);
							break;
						default:
							break;
					}
		}
		catch (Exception e)
		{
			r.instructions = null;
			r.error = e.msg;
			instructionAtOffset[] = 0;
		}
		pos = end;

		r.exceptions.length = readU30();
		foreach (ref value; r.exceptions)
		{
			value = readExceptionInfo();
			translateLabel(value.from);
			translateLabel(value.to);
			translateLabel(value.target);
		}
		r.traits.length = readU30();
		foreach (ref value; r.traits)
			value = readTrait();
		return r;
	}

	ABCFile.ExceptionInfo readExceptionInfo()
	{
		ABCFile.ExceptionInfo r;
		r.from.absoluteOffset = readU30();
		r.to.absoluteOffset = readU30();
		r.target.absoluteOffset = readU30();
		r.excType = readU30();
		r.varName = readU30();
		return r;
	}
}

private final class ABCWriter
{
	ABCFile abc;
	ubyte[] buf;
	size_t pos;

	this(ABCFile abc)
	{
		this.abc = abc;
		this.buf = new ubyte[1024];

		writeU16(abc.minorVersion);
		writeU16(abc.majorVersion);

		writeU30(abc.ints.length <= 1 ? 0 : abc.ints.length);
		foreach (ref value; abc.ints[1..$])
			writeS32(value);

		writeU30(abc.uints.length <= 1 ? 0 : abc.uints.length);
		foreach (ref value; abc.uints[1..$])
			writeU32(value);

		writeU30(abc.doubles.length <= 1 ? 0 : abc.doubles.length);
		foreach (ref value; abc.doubles[1..$])
			writeD64(value);

		writeU30(abc.strings.length <= 1 ? 0 : abc.strings.length);
		foreach (ref value; abc.strings[1..$])
			writeString(value);

		writeU30(abc.namespaces.length <= 1 ? 0 : abc.namespaces.length);
		foreach (ref value; abc.namespaces[1..$])
			writeNamespace(value);

		writeU30(abc.namespaceSets.length <= 1 ? 0 : abc.namespaceSets.length);
		foreach (ref value; abc.namespaceSets[1..$])
			writeNamespaceSet(value);

		writeU30(abc.multinames.length <= 1 ? 0 : abc.multinames.length);
		foreach (ref value; abc.multinames[1..$])
			writeMultiname(value);

		writeU30(abc.methods.length);
		foreach (ref value; abc.methods)
			writeMethodInfo(value);

		writeU30(abc.metadata.length);
		foreach (ref value; abc.metadata)
			writeMetadata(value);

		writeU30(abc.instances.length);
		foreach (ref value; abc.instances)
			writeInstance(value);

		assert(abc.classes.length == abc.instances.length, "Number of classes and instances differs");
		foreach (ref value; abc.classes)
			writeClass(value);

		writeU30(abc.scripts.length);
		foreach (ref value; abc.scripts)
			writeScript(value);

		writeU30(abc.bodies.length);
		foreach (ref value; abc.bodies)
			writeMethodBody(value);

		buf.length = pos;
	}

	void writeU8(ubyte v)
	{
		if (pos == buf.length)
			buf.length = buf.length * 2;
		buf[pos++] = v;
	}

	void writeU16(ushort v)
	{
		writeU8(v&0xFF);
		writeU8(cast(ubyte)(v>>8));
	}

	void writeS24(int v)
	{
		writeU8(v&0xFF);
		writeU8(cast(ubyte)(v>>8));
		writeU8(cast(ubyte)(v>>16));
	}

	void writeU32(ulong v)
	{
		if ( v < 128)
		{
			writeU8(cast(ubyte)(v));
		}
		else if ( v < 16384)
		{
			writeU8(cast(ubyte)((v & 0x7F) | 0x80));
			writeU8(cast(ubyte)((v >> 7) & 0x7F));
		}
		else if ( v < 2097152)
		{
			writeU8(cast(ubyte)((v & 0x7F) | 0x80));
			writeU8(cast(ubyte)((v >> 7) | 0x80));
			writeU8(cast(ubyte)((v >> 14) & 0x7F));
		}
		else if (  v < 268435456)
		{
			writeU8(cast(ubyte)((v & 0x7F) | 0x80));
			writeU8(cast(ubyte)(v >> 7 | 0x80));
			writeU8(cast(ubyte)(v >> 14 | 0x80));
			writeU8(cast(ubyte)((v >> 21) & 0x7F));
		}
		else
		{
			writeU8(cast(ubyte)((v & 0x7F) | 0x80));
			writeU8(cast(ubyte)(v >> 7 | 0x80));
			writeU8(cast(ubyte)(v >> 14 | 0x80));
			writeU8(cast(ubyte)(v >> 21 | 0x80));
			writeU8(cast(ubyte)((v >> 28) & 0x0F));
		}
	}

	void writeS32(long v)
	{
		writeU32(cast(ulong)v);
	}

	void writeU30(ulong v)
	{
		enforce(v < (1<<30));
		writeU32(v);
	}

	void writeExact(const(void)* ptr, size_t len)
	{
		while (pos+len > buf.length)
			buf.length = buf.length * 2;
		buf[pos..pos+len] = (cast(ubyte*)ptr)[0..len];
		pos += len;
	}

	void writeD64(double v)
	{
		static assert(double.sizeof == 8);
		writeExact(&v, 8);
	}

	void writeString(string v)
	{
		writeU30(v.length);
		writeExact(v.ptr, v.length);
	}

	void writeBytes(ubyte[] v)
	{
		writeU30(v.length);
		writeExact(v.ptr, v.length);
	}

	void writeNamespace(ref ABCFile.Namespace v)
	{
		writeU8(v.kind);
		writeU30(v.name);
	}

	void writeNamespaceSet(uint[] v)
	{
		writeU30(v.length);
		foreach (value; v)
			writeU30(value);
	}

	void writeMultiname(ref ABCFile.Multiname v)
	{
		writeU8(v.kind);
		switch (v.kind)
		{
			case ASType.QName:
			case ASType.QNameA:
				writeU30(v.QName.ns);
				writeU30(v.QName.name);
				break;
			case ASType.RTQName:
			case ASType.RTQNameA:
				writeU30(v.RTQName.name);
				break;
			case ASType.RTQNameL:
			case ASType.RTQNameLA:
				break;
			case ASType.Multiname:
			case ASType.MultinameA:
				writeU30(v.Multiname.name);
				writeU30(v.Multiname.nsSet);
				break;
			case ASType.MultinameL:
			case ASType.MultinameLA:
				writeU30(v.MultinameL.nsSet);
				break;
			case ASType.TypeName:
				writeU30(v.TypeName.name);
				writeU30(v.TypeName.params.length);
				foreach (value; v.TypeName.params)
					writeU30(value);
				break;
			default:
				throw new Exception("Unknown Multiname kind");
		}
	}

	void writeMethodInfo(ref ABCFile.MethodInfo v)
	{
		writeU30(v.paramTypes.length);
		writeU30(v.returnType);
		foreach (value; v.paramTypes)
			writeU30(value);
		writeU30(v.name);
		writeU8(v.flags);
		if (v.flags & MethodFlags.HAS_OPTIONAL)
		{
			writeU30(v.options.length);
			foreach (ref option; v.options)
				writeOptionDetail(option);
		}
		if (v.flags & MethodFlags.HAS_PARAM_NAMES)
		{
			assert(v.paramNames.length == v.paramTypes.length, "Mismatching number of parameter names and types");
			foreach (value; v.paramNames)
				writeU30(value);
		}
	}

	void writeOptionDetail(ref ABCFile.OptionDetail v)
	{
		writeU30(v.val);
		writeU8(v.kind);
	}

	void writeMetadata(ref ABCFile.Metadata v)
	{
		writeU30(v.name);
		assert(v.keys.length == v.values.length);
		writeU30(v.keys.length);
		foreach (key; v.keys)
			writeU30(key);
		foreach (value; v.values)
			writeU30(value);
	}

	void writeInstance(ref ABCFile.Instance v)
	{
		writeU30(v.name);
		writeU30(v.superName);
		writeU8(v.flags);
		if (v.flags & InstanceFlags.ProtectedNs)
			writeU30(v.protectedNs);
		writeU30(v.interfaces.length);
		foreach (ref value; v.interfaces)
			writeU30(value);
		writeU30(v.iinit);
		writeU30(v.traits.length);
		foreach (ref value; v.traits)
			writeTrait(value);
	}

	void writeTrait(ABCFile.TraitsInfo v)
	{
		writeU30(v.name);
		writeU8(v.kindAttr);
		switch (v.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				writeU30(v.Slot.slotId);
				writeU30(v.Slot.typeName);
				writeU30(v.Slot.vindex);
				if (v.Slot.vindex)
					writeU8(v.Slot.vkind);
				break;
			case TraitKind.Class:
				writeU30(v.Class.slotId);
				writeU30(v.Class.classi);
				break;
			case TraitKind.Function:
				writeU30(v.Function.slotId);
				writeU30(v.Function.functioni);
				break;
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				writeU30(v.Method.dispId);
				writeU30(v.Method.method);
				break;
			default:
				throw new Exception("Unknown trait kind");
		}
		if (v.attr & TraitAttributes.Metadata)
		{
			writeU30(v.metadata.length);
			foreach (value; v.metadata)
				writeU30(value);
		}
	}

	void writeClass(ABCFile.Class v)
	{
		writeU30(v.cinit);
		writeU30(v.traits.length);
		foreach (ref value; v.traits)
			writeTrait(value);
	}

	void writeScript(ABCFile.Script v)
	{
		writeU30(v.sinit);
		writeU30(v.traits.length);
		foreach (ref value; v.traits)
			writeTrait(value);
	}

	void writeMethodBody(ABCFile.MethodBody v)
	{
		writeU30(v.method);
		writeU30(v.maxStack);
		writeU30(v.localCount);
		writeU30(v.initScopeDepth);
		writeU30(v.maxScopeDepth);

		auto instructionOffsets = new size_t[v.instructions.length+1];

		ptrdiff_t resolveLabel(ref ABCFile.Label label) { return instructionOffsets[label.index]+label.offset; }

		{
			// we don't know the length before writing all the instructions - swap buffer with a temporary one
			auto globalBuf = buf;
			auto globalPos = pos;
			static ubyte[1024*16] methodBuf;
			buf = methodBuf[];
			pos = 0;

			struct Fixup { ABCFile.Label target; size_t pos, base; }
			Fixup[] fixups;

			foreach (ii, ref instruction; v.instructions)
			{
				auto instructionOffset = pos;
				instructionOffsets[ii] = instructionOffset;

				writeU8(instruction.opcode);

				if (instruction.arguments.length != opcodeInfo[instruction.opcode].argumentTypes.length)
					throw new Exception("Mismatching number of arguments");

				foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
					final switch (type)
					{
						case OpcodeArgumentType.Unknown:
							throw new Exception("Don't know how to encode OP_" ~ opcodeInfo[instruction.opcode].name);

						case OpcodeArgumentType.UByteLiteral:
							writeU8(instruction.arguments[i].ubytev);
							break;
						case OpcodeArgumentType.IntLiteral:
							writeS32(instruction.arguments[i].intv);
							break;
						case OpcodeArgumentType.UIntLiteral:
							writeU32(instruction.arguments[i].uintv);
							break;

						case OpcodeArgumentType.Int:
						case OpcodeArgumentType.UInt:
						case OpcodeArgumentType.Double:
						case OpcodeArgumentType.String:
						case OpcodeArgumentType.Namespace:
						case OpcodeArgumentType.Multiname:
						case OpcodeArgumentType.Class:
						case OpcodeArgumentType.Method:
							writeU30(instruction.arguments[i].index);
							break;

						case OpcodeArgumentType.JumpTarget:
							fixups ~= Fixup(instruction.arguments[i].jumpTarget, pos, pos+3);
							writeS24(0);
							break;

						case OpcodeArgumentType.SwitchDefaultTarget:
							fixups ~= Fixup(instruction.arguments[i].jumpTarget, pos, instructionOffset);
							writeS24(0);
							break;

						case OpcodeArgumentType.SwitchTargets:
							if (instruction.arguments[i].switchTargets.length < 1)
								throw new Exception("Too few switch cases");
							writeU30(instruction.arguments[i].switchTargets.length-1);
							foreach (off; instruction.arguments[i].switchTargets)
							{
								fixups ~= Fixup(off, pos, instructionOffset);
								writeS24(0);
							}
							break;
					}
			}

			buf.length = pos;
			instructionOffsets[v.instructions.length] = pos;

			foreach (ref fixup; fixups)
			{
				pos = fixup.pos;
				writeS24(to!int(cast(ptrdiff_t)(resolveLabel(fixup.target)-fixup.base)));
			}

			auto code = buf;
			// restore global buffer
			buf = globalBuf;
			pos = globalPos;

			writeBytes(code);
		}

		writeU30(v.exceptions.length);
		foreach (ref value; v.exceptions)
		{
			value.from.absoluteOffset = resolveLabel(value.from);
			value.to.absoluteOffset = resolveLabel(value.to);
			value.target.absoluteOffset = resolveLabel(value.target);
			writeExceptionInfo(value);
		}
		writeU30(v.traits.length);
		foreach (ref value; v.traits)
			writeTrait(value);
	}

	void writeExceptionInfo(ABCFile.ExceptionInfo v)
	{
		writeU30(v.from.absoluteOffset);
		writeU30(v.to.absoluteOffset);
		writeU30(v.target.absoluteOffset);
		writeU30(v.excType);
		writeU30(v.varName);
	}
}

class ABCTraitsVisitor
{
	ABCFile abc;

	this(ABCFile abc)
	{
		this.abc = abc;
	}

	final void run()
	{
		foreach (ref v; abc.instances)
			visitTraits(v.traits);
		foreach (ref v; abc.classes)
			visitTraits(v.traits);
		foreach (ref v; abc.scripts)
			visitTraits(v.traits);
		foreach (ref v; abc.bodies)
			visitTraits(v.traits);
	}

	final void visitTraits(ABCFile.TraitsInfo[] traits)
	{
		foreach (ref trait; traits)
			visitTrait(trait);
	}

	abstract void visitTrait(ref ABCFile.TraitsInfo trait);
}
