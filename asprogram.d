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

module asprogram;

import std.algorithm;
import core.stdc.string;
import abcfile;
import autodata;

/**
 * Represents a hierarchically-organized ActionScript program,
 * with all constants expanded and bytecode disassembled to separate instructions.
 */

final class ASProgram
{
	ushort minorVersion, majorVersion;
	Script[] scripts;
	Class[] orphanClasses;
	Method[] orphanMethods;

	static class Namespace
	{
		ASType kind;
		string name;

		uint id; // unique index for private/homonym namespaces

		mixin AutoCompare;
		mixin AutoToString;
		mixin ProcessAllData;
	}

	static class Multiname
	{
		ASType kind;
		union
		{
			struct _QName
			{
				Namespace ns;
				string name;
			} _QName vQName;
			struct _RTQName
			{
				string name;
			} _RTQName vRTQName;
			struct _RTQNameL
			{
			} _RTQNameL vRTQNameL;
			struct _Multiname
			{
				string name;
				Namespace[] nsSet;
			} _Multiname vMultiname;
			struct _MultinameL
			{
				Namespace[] nsSet;
			} _MultinameL vMultinameL;
			struct _TypeName
			{
				Multiname name;
				Multiname[] params;
			} _TypeName vTypeName;
		}

		mixin AutoCompare;
		mixin AutoToString;

		R processData(R, string prolog, string epilog, H)(ref H handler) const
		{
			mixin(prolog);
			mixin(addAutoField("kind"));
			switch (kind)
			{
				case ASType.QName:
				case ASType.QNameA:
					mixin(addAutoField("vQName.ns"));
					mixin(addAutoField("vQName.name"));
					break;
				case ASType.RTQName:
				case ASType.RTQNameA:
					mixin(addAutoField("vRTQName.name"));
					break;
				case ASType.RTQNameL:
				case ASType.RTQNameLA:
					break;
				case ASType.Multiname:
				case ASType.MultinameA:
					mixin(addAutoField("vMultiname.name"));
					mixin(addAutoField("vMultiname.nsSet"));
					break;
				case ASType.MultinameL:
				case ASType.MultinameLA:
					mixin(addAutoField("vMultinameL.nsSet"));
					break;
				case ASType.TypeName:
					mixin(addAutoField("vTypeName.name"));
					mixin(addAutoField("vTypeName.params"));
					break;
				default:
					throw new .Exception("Unknown Multiname kind");
			}
			mixin(epilog);
		}

		private Multiname[] toQNames()
		{
			switch (kind)
			{
				case ASType.QName:
				case ASType.QNameA:
					return [this];
				case ASType.Multiname:
				case ASType.MultinameA:
					Multiname[] result;
					foreach (ns; vMultiname.nsSet)
					{
						auto n = new Multiname;
						n.kind = kind==ASType.Multiname ? ASType.QName : ASType.QNameA;
						n.vQName.ns = ns;
						n.vQName.name = vMultiname.name;
						result ~= n;
					}
					return result;
				default:
					throw new .Exception("Can't expand Multiname of this kind");
			}
		}
	}

	static class Method
	{
		Multiname[] paramTypes;
		Multiname returnType;
		string name;
		ubyte flags; // MethodFlags bitmask
		Value[] options;
		string[] paramNames;

		uint id; // file index

		MethodBody vbody;
	}

	static class Metadata
	{
		string name;
		string[] keys, values;

		mixin AutoCompare;
		mixin ProcessAllData;
	}

	static class Instance
	{
		Multiname name;
		Multiname superName;
		ubyte flags; // InstanceFlags bitmask
		Namespace protectedNs;
		Multiname[] interfaces;
		Method iinit;
		Trait[] traits;
	}

	struct Value
	{
		ASType vkind;
		union
		{
			long vint;             // Integer
			ulong vuint;           // UInteger
			double vdouble;       // Double
			string vstring;       // String
			Namespace vnamespace; // Namespace, PackageNamespace, PackageInternalNs, ProtectedNamespace, ExplicitNamespace, StaticProtectedNs, PrivateNamespace
		}
	}

	struct Trait
	{
		Multiname name;
		TraitKind kind;
		ubyte attr; // TraitAttributes bitmask

		union
		{
			struct _Slot
			{
				uint slotId;
				Multiname typeName;
				Value value;
			} _Slot vSlot;
			struct _Class
			{
				uint slotId;
				Class vclass;
			} _Class vClass;
			struct _Function
			{
				uint slotId;
				Method vfunction;
			} _Function vFunction;
			struct _Method
			{
				uint dispId;
				Method vmethod;
			} _Method vMethod;
		}
		Metadata[] metadata;
	}

	static class Class
	{
		Method cinit;
		Trait[] traits;

		Instance instance;

		override string toString()
		{
			return instance.name.toString();
		}
	}

	static class Script
	{
		Method sinit;
		Trait[] traits;
	}

	static class MethodBody
	{
		Method method;
		uint maxStack;
		uint localCount;
		uint initScopeDepth;
		uint maxScopeDepth;
		Instruction[] instructions;
		Exception[] exceptions;
		Trait[] traits;

		string error;
		ubyte[] rawBytes;
	}

	struct Instruction
	{
		Opcode opcode;
		union Argument
		{
			ubyte ubytev;

			long intv;
			ulong uintv;

			// int/uint constants are in intv/uintv
			double doublev;
			string stringv;
			Namespace namespacev;
			Multiname multinamev;
			Class classv;
			Method methodv;

			ABCFile.Label jumpTarget;
			ABCFile.Label[] switchTargets;
		}
		Argument[] arguments;
	}

	struct Exception
	{
		ABCFile.Label from, to, target;
		Multiname excType;
		Multiname varName;
	}

	this()
	{
		majorVersion = 46;
		minorVersion = 16;
	}

	static ASProgram fromABC(ABCFile abc)
	{
		return (new ABCtoAS(abc)).as;
	}

	ABCFile toABC()
	{
		return (new AStoABC(this)).abc;
	}
}

private final class ABCtoAS
{
	ASProgram as;
	ABCFile abc;

	ASProgram.Namespace[] namespaces;
	ASProgram.Namespace[][] namespaceSets;
	ASProgram.Multiname[] multinames;
	ASProgram.Method[] methods;
	ASProgram.Metadata[] metadata;
	ASProgram.Instance[] instances;
	ASProgram.Class[] classes;

	bool[] methodAdded;
	bool[] classAdded;

	ASProgram.Method getMethod(uint index)
	{
		methodAdded[index] = true;
		return methods[index];
	}

	ASProgram.Class getClass(uint index)
	{
		classAdded[index] = true;
		return classes[index];
	}

	ASProgram.Value convertValue(ASType kind, uint val)
	{
		ASProgram.Value o;
		o.vkind = kind;
		switch (o.vkind)
		{
			case ASType.Integer:
				o.vint = abc.ints[val]; // WARNING: discarding extra bits
				break;
			case ASType.UInteger:
				o.vuint = abc.uints[val]; // WARNING: discarding extra bits
				break;
			case ASType.Double:
				o.vdouble = abc.doubles[val];
				break;
			case ASType.Utf8:
				o.vstring = abc.strings[val];
				break;
			case ASType.Namespace:
			case ASType.PackageNamespace:
			case ASType.PackageInternalNs:
			case ASType.ProtectedNamespace:
			case ASType.ExplicitNamespace:
			case ASType.StaticProtectedNs:
			case ASType.PrivateNamespace:
				o.vnamespace = namespaces[val];
				break;
			case ASType.True:
			case ASType.False:
			case ASType.Null:
			case ASType.Undefined:
				break;
			default:
				throw new Exception("Unknown type");
		}
		return o;
	}

	ASProgram.Namespace convertNamespace(ref ABCFile.Namespace namespace, int id)
	{
		auto n = new ASProgram.Namespace();
		n.kind = namespace.kind;
		n.name = abc.strings[namespace.name];
		n.id = id;
		return n;
	}

	ASProgram.Namespace[] convertNamespaceSet(uint[] namespaceSet)
	{
		if (namespaceSet is null)
			return null;
		auto n = new ASProgram.Namespace[namespaceSet.length];
		foreach (j, namespace; namespaceSet)
			n[j] = namespaces[namespace];
		if (namespaceSet.length == 0)
		{
			n.length = 1;
			n.length = 0;
			assert (n !is null); // empty, but not null
		}
		return n;
	}

	ASProgram.Multiname convertMultiname(ref ABCFile.Multiname multiname)
	{
		auto n = new ASProgram.Multiname();
		n.kind = multiname.kind;
		switch (multiname.kind)
		{
			case ASType.QName:
			case ASType.QNameA:
				n.vQName.ns = namespaces[multiname.QName.ns];
				n.vQName.name = abc.strings[multiname.QName.name];
				break;
			case ASType.RTQName:
			case ASType.RTQNameA:
				n.vRTQName.name = abc.strings[multiname.RTQName.name];
				break;
			case ASType.RTQNameL:
			case ASType.RTQNameLA:
				break;
			case ASType.Multiname:
			case ASType.MultinameA:
				n.vMultiname.name = abc.strings[multiname.Multiname.name];
				n.vMultiname.nsSet = namespaceSets[multiname.Multiname.nsSet];
				break;
			case ASType.MultinameL:
			case ASType.MultinameLA:
				n.vMultinameL.nsSet = namespaceSets[multiname.MultinameL.nsSet];
				break;
			case ASType.TypeName:
				// handled in postConvertMultiname
				break;
			default:
				throw new Exception("Unknown Multiname kind");
		}
		return n;
	}

	void postConvertMultiname(ref ABCFile.Multiname multiname, ASProgram.Multiname n)
	{
		switch (multiname.kind)
		{
			case ASType.TypeName:
				n.vTypeName.name = multinames[multiname.TypeName.name];
				n.vTypeName.params.length = multiname.TypeName.params.length;
				foreach (j, param; multiname.TypeName.params)
					n.vTypeName.params[j] = multinames[param];
				break;
			default:
				break;
		}
	}

	ASProgram.Method convertMethod(ref ABCFile.MethodInfo method, uint id)
	{
		auto n = new ASProgram.Method();
		n.paramTypes.length = method.paramTypes.length;
		foreach (j, param; method.paramTypes)
			n.paramTypes[j] = multinames[param];
		n.returnType = multinames[method.returnType];
		n.name = abc.strings[method.name];
		n.flags = method.flags;
		n.options.length = method.options.length;
		foreach (j, ref option; method.options)
			n.options[j] = convertValue(option.kind, option.val);
		n.paramNames.length = method.paramNames.length;
		foreach (j, name; method.paramNames)
			n.paramNames[j] = abc.strings[name];
		n.id = id;
		return n;
	}

	ASProgram.Metadata convertMetadata(ref ABCFile.Metadata md)
	{
		auto n = new ASProgram.Metadata();
		n.name = abc.strings[md.name];
		n.keys.length = md.keys.length;
		foreach (j, key; md.keys)
			n.keys[j] = abc.strings[key];
		n.values.length = md.values.length;
		foreach (j, value; md.values)
			n.values[j] = abc.strings[value];
		return n;
	}

	ASProgram.Trait[] convertTraits(ABCFile.TraitsInfo[] traits)
	{
		auto r = new ASProgram.Trait[traits.length];
		foreach (i, ref trait; traits)
		{
			r[i].name = multinames[trait.name];
			r[i].kind = trait.kind;
			r[i].attr = trait.attr;
			switch (trait.kind)
			{
				case TraitKind.Slot:
				case TraitKind.Const:
					r[i].vSlot.slotId = trait.Slot.slotId;
					r[i].vSlot.typeName = multinames[trait.Slot.typeName];
					r[i].vSlot.value = convertValue(trait.Slot.vkind, trait.Slot.vindex);
					break;
				case TraitKind.Class:
					r[i].vClass.slotId = trait.Class.slotId;
					if (classes.length==0 || classes[trait.Class.classi] is null)
						throw new Exception("Forward class reference");
					r[i].vClass.vclass = getClass(trait.Class.classi);
					break;
				case TraitKind.Function:
					r[i].vFunction.slotId = trait.Function.slotId;
					r[i].vFunction.vfunction = getMethod(trait.Function.functioni);
					break;
				case TraitKind.Method:
				case TraitKind.Getter:
				case TraitKind.Setter:
					r[i].vMethod.dispId = trait.Method.dispId;
					r[i].vMethod.vmethod = getMethod(trait.Method.method);
					break;
				default:
					throw new Exception("Unknown trait kind");
			}
			r[i].metadata.length = trait.metadata.length;
			foreach (j, index; trait.metadata)
				r[i].metadata[j] = metadata[index];
		}
		return r;
	}

	ASProgram.Instance convertInstance(ref ABCFile.Instance instance)
	{
		auto n = new ASProgram.Instance();
		n.name = multinames[instance.name];
		n.superName = multinames[instance.superName];
		n.flags = instance.flags;
		n.protectedNs = namespaces[instance.protectedNs];
		n.interfaces.length = instance.interfaces.length;
		foreach (j, intf; instance.interfaces)
			n.interfaces[j] = multinames[intf];
		n.iinit = getMethod(instance.iinit);
		n.traits = convertTraits(instance.traits);
		return n;
	}

	ASProgram.Class convertClass(ref ABCFile.Class vclass, uint i)
	{
		auto n = new ASProgram.Class();
		n.cinit = getMethod(vclass.cinit);
		n.traits = convertTraits(vclass.traits);
		n.instance = instances[i];
		return n;
	}

	ASProgram.Script convertScript(ref ABCFile.Script script)
	{
		auto n = new ASProgram.Script;
		n.sinit = getMethod(script.sinit);
		n.traits = convertTraits(script.traits);
		return n;
	}

	ASProgram.MethodBody convertBody(ref ABCFile.MethodBody vbody)
	{
		auto n = new ASProgram.MethodBody;
		n.method = methods[vbody.method];
		n.maxStack = vbody.maxStack;
		n.localCount = vbody.localCount;
		n.initScopeDepth = vbody.initScopeDepth;
		n.maxScopeDepth = vbody.maxScopeDepth;
		n.instructions.length = vbody.instructions.length;
		foreach (ii, ref instruction; vbody.instructions)
			n.instructions[ii] = convertInstruction(instruction);
		n.exceptions.length = vbody.exceptions.length;
		foreach (j, ref exc; vbody.exceptions)
		{
			auto e = &n.exceptions[j];
			e.from = exc.from;
			e.to = exc.to;
			e.target = exc.target;
			e.excType = multinames[exc.excType];
			e.varName = multinames[exc.varName];
		}
		n.traits = convertTraits(vbody.traits);
		n.error = vbody.error;
		n.rawBytes = vbody.rawBytes;
		return n;
	}

	ASProgram.Instruction convertInstruction(ref ABCFile.Instruction instruction)
	{
		ASProgram.Instruction r;
		r.opcode = instruction.opcode;
		r.arguments.length = instruction.arguments.length;

		foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
			final switch (type)
			{
				case OpcodeArgumentType.Unknown:
					throw new Exception("Don't know how to convert OP_" ~ opcodeInfo[instruction.opcode].name);

				case OpcodeArgumentType.UByteLiteral:
					r.arguments[i].ubytev = instruction.arguments[i].ubytev;
					break;
				case OpcodeArgumentType.IntLiteral:
					r.arguments[i].intv = instruction.arguments[i].intv;
					break;
				case OpcodeArgumentType.UIntLiteral:
					r.arguments[i].uintv = instruction.arguments[i].uintv;
					break;

				case OpcodeArgumentType.Int:
					r.arguments[i].intv = abc.ints[instruction.arguments[i].index];
					break;
				case OpcodeArgumentType.UInt:
					r.arguments[i].uintv = abc.uints[instruction.arguments[i].index];
					break;
				case OpcodeArgumentType.Double:
					r.arguments[i].doublev = abc.doubles[instruction.arguments[i].index];
					break;
				case OpcodeArgumentType.String:
					r.arguments[i].stringv = abc.strings[instruction.arguments[i].index];
					break;
				case OpcodeArgumentType.Namespace:
					r.arguments[i].namespacev = namespaces.checkedGet(instruction.arguments[i].index);
					break;
				case OpcodeArgumentType.Multiname:
					r.arguments[i].multinamev = multinames.checkedGet(instruction.arguments[i].index);
					break;
				case OpcodeArgumentType.Class:
					r.arguments[i].classv = classes.checkedGet(instruction.arguments[i].index);
					break;
				case OpcodeArgumentType.Method:
					r.arguments[i].methodv = methods.checkedGet(instruction.arguments[i].index);
					break;

				case OpcodeArgumentType.JumpTarget:
				case OpcodeArgumentType.SwitchDefaultTarget:
					r.arguments[i].jumpTarget = instruction.arguments[i].jumpTarget;
					break;

				case OpcodeArgumentType.SwitchTargets:
					r.arguments[i].switchTargets = instruction.arguments[i].switchTargets;
					break;
			}
		return r;
	}

	this(ABCFile abc)
	{
		this.as = new ASProgram();
		this.abc = abc;

		as.minorVersion = abc.minorVersion;
		as.majorVersion = abc.majorVersion;

		namespaces.length = abc.namespaces.length;
		foreach (uint i, ref namespace; abc.namespaces)
			if (i)
				namespaces[i] = convertNamespace(namespace, i);

		namespaceSets.length = abc.namespaceSets.length;
		foreach (i, namespaceSet; abc.namespaceSets)
			if (i)
				namespaceSets[i] = convertNamespaceSet(namespaceSet);

		multinames.length = abc.multinames.length;
		foreach (i, ref multiname; abc.multinames)
			if (i)
				multinames[i] = convertMultiname(multiname);
		foreach (i, ref multiname; abc.multinames)
			if (i)
				postConvertMultiname(multiname, multinames[i]);

		methods.length = methodAdded.length = abc.methods.length;
		foreach (uint i, ref method; abc.methods)
			methods[i] = convertMethod(method, i);

		metadata.length = abc.metadata.length;
		foreach (i, ref md; abc.metadata)
			metadata[i] = convertMetadata(md);

		instances.length = classAdded.length = abc.instances.length;
		foreach (i, ref instance; abc.instances)
			instances[i] = convertInstance(instance);

		classes.length = abc.classes.length;
		foreach (uint i, ref vclass; abc.classes)
			classes[i] = convertClass(vclass, i);

		as.scripts.length = abc.scripts.length;
		foreach (i, ref script; abc.scripts)
			as.scripts[i] = convertScript(script);

		foreach (i, ref vbody; abc.bodies)
			methods[vbody.method].vbody = convertBody(vbody);

		foreach (i, b; classAdded)
			if (!b)
				as.orphanClasses ~= classes[i];

		foreach (i, b; methodAdded)
			if (!b)
				as.orphanMethods ~= methods[i];
	}
}

private final class AStoABC : ASVisitor
{
	ABCFile abc;

	static bool isNull(T)(T value)
	{
		//static if (is (T == class) || is(T == string))
		//static if (is (T == class) || is(T U : U[]))
		static if (is(typeof(value is null)))
			return value is null;
		else
		static if (is (T == long))
			return value == ABCFile.NULL_INT;
		else
		static if (is (T == ulong))
			return value == ABCFile.NULL_UINT;
		else
		static if (is (T == double))
			return value == ABCFile.NULL_DOUBLE;
		else
			return value == T.init;
	}

	static void move(T)(T[] array, size_t from, size_t to)
	{
		assert(from<array.length && to<array.length);
		if (from == to)
			return;
		T t = array[from];
		if (from < to)
			memmove(array.ptr+from, array.ptr+from+1, (to-from)*T.sizeof);
		else
			memmove(array.ptr+to+1, array.ptr+to,     (from-to)*T.sizeof);
		array[to] = t;
	}

	/// Maintain an unordered set of values; sort/index by usage count
	struct ConstantPool(T, bool haveNull = true)
	{
		alias immutable(T) I;

		struct Entry
		{
			uint hits;
			T value;
			uint index;

			mixin AutoCompare;

			R processData(R, string prolog, string epilog, H)(ref H handler) const
			{
				mixin(prolog);
				mixin(addAutoField("hits", true));
				mixin(addAutoField("value"));
				mixin(epilog);
			}
		}

		Entry[immutable(T)] pool;
		T[] values;

		bool add(T value) // return true if added
		{
			if (haveNull && isNull(value))
				return false;
			auto cp = cast(I)value in pool;
			if (cp is null)
			{
				pool[cast(I)value] = Entry(1, value);
				return true;
			}
			else
			{
				cp.hits++;
				return false;
			}
		}

		bool notAdded(T value)
		{
			auto ep = cast(I)value in pool;
			if (ep)
				ep.hits++;
			return !((haveNull && isNull(value)) || ep);
		}

		void finalize()
		{
			auto all = pool.values;
			all.sort;
			enum { NullOffset = haveNull ? 1 : 0 }
			values.length = all.length + NullOffset;
			foreach (uint i, ref c; all)
			{
				pool[cast(I)c.value].index = i + NullOffset;
				values[i + NullOffset] = c.value;
			}
		}

		uint get(T value)
		{
			if (haveNull && isNull(value))
				return 0;
			return pool[cast(I)value].index;
		}
	}

	/// Pair an index with class instances
	struct ReferencePool(T : Object)
	{
		struct Entry
		{
			uint hits;
			void* object;
			uint addIndex, index;
			void*[] parents;

			mixin AutoToString;
			mixin ProcessAllData;
		}

		Entry[void*] pool;
		T[] objects;

		bool add(T obj) // return true if added
		{
			if (obj is null)
				return false;
			auto p = cast(void*)obj;
			auto rp = p in pool;
			if (rp is null)
			{
				pool[p] = Entry(1, p, to!uint(pool.length));
				return true;
			}
			else
			{
				rp.hits++;
				return false;
			}
		}

		bool notAdded(T obj)
		{
			auto ep = (cast(void*)obj) in pool;
			if (ep)
				ep.hits++;
			return !(obj is null || ep);
		}

		void registerDependency(T from, T to)
		{
			auto pfrom = (cast(void*)from) in pool;
			assert(pfrom, "Unknown dependency source");
			auto vto = cast(void*)to;
			auto pto = vto in pool;
			assert(pto, "Unknown dependency target");
			assert(!pfrom.parents.contains(vto), "Dependency already set");
			pfrom.parents ~= vto;
		}

		T[] getPreliminaryObjects()
		{
			return cast(T[])pool.keys;
		}

		void finalize()
		{
			// create array
			auto all = new Entry*[pool.length];
			int i=0;
			foreach (ref e; pool)
				all[i++] = &e;

			// sort
			sort!q{a.hits > b.hits || (a.hits == b.hits && a.addIndex < b.addIndex)}(all);

			// topographical sort
			topSort:

			// update indices
			foreach (uint j, e; all)
				e.index = j;

			foreach (ref a; pool)
				foreach (parent; a.parents)
				{
					auto pb = parent in pool;
					assert(pb !is null, "Can't find referenced object");
					if (pb.index > a.index)
					{
						move(all, pb.index, a.index);
						goto topSort;
					}
				}

			objects.length = i;
			foreach (j, e; all)
				objects[j] = cast(T)e.object;
		}

		uint get(T obj)
		{
			assert(obj !is null, "Trying to get index of null object");
			return pool[cast(void*)obj].index;
		}
	}

	ConstantPool!(long) ints;
	ConstantPool!(ulong) uints;
	ConstantPool!(double) doubles;
	ConstantPool!(string) strings;
	ConstantPool!(ASProgram.Namespace) namespaces;
	ConstantPool!(ASProgram.Namespace[]) namespaceSets;
	ConstantPool!(ASProgram.Multiname) multinames;
	ConstantPool!(ASProgram.Metadata, false) metadatas;
	ReferencePool!(ASProgram.Class) classes;
	ReferencePool!(ASProgram.Method) methods;

	override void visitInt(long v) { ints.add(v); }
	override void visitUint(ulong v) { uints.add(v); }
	override void visitDouble(double v) { doubles.add(v); }
	override void visitString(string v) { strings.add(v); }

	override void visitNamespace(ASProgram.Namespace ns)
	{
		if (namespaces.add(ns))
			super.visitNamespace(ns);
	}

	override void visitNamespaceSet(ASProgram.Namespace[] nsSet)
	{
		if (namespaceSets.add(nsSet))
			super.visitNamespaceSet(nsSet);
	}

	override void visitMultiname(ASProgram.Multiname multiname)
	{
		if (multinames.notAdded(multiname))
		{
			super.visitMultiname(multiname);
			bool r = multinames.add(multiname);
			assert(r, "Recursive multiname reference");
		}
	}

	override void visitMetadata(ASProgram.Metadata metadata)
	{
		if (metadatas.add(metadata))
			super.visitMetadata(metadata);
	}

	override void visitClass(ASProgram.Class vclass)
	{
		if (classes.add(vclass))
			super.visitClass(vclass);
	}

	override void visitMethod(ASProgram.Method method)
	{
		if (methods.add(method))
			super.visitMethod(method);
	}

	uint getValueIndex(ref ASProgram.Value value)
	{
		switch (value.vkind)
		{
			case ASType.Integer:
				return ints.get(value.vint);
			case ASType.UInteger:
				return uints.get(value.vuint);
			case ASType.Double:
				return doubles.get(value.vdouble);
			case ASType.Utf8:
				return strings.get(value.vstring);
			case ASType.Namespace:
			case ASType.PackageNamespace:
			case ASType.PackageInternalNs:
			case ASType.ProtectedNamespace:
			case ASType.ExplicitNamespace:
			case ASType.StaticProtectedNs:
			case ASType.PrivateNamespace:
				return namespaces.get(value.vnamespace);
			case ASType.True:
			case ASType.False:
			case ASType.Null:
			case ASType.Undefined:
				return value.vkind; // must be non-zero for True/False/Null
			default:
				throw new Exception("Unknown type");
		}
	}

	void registerClassDependencies()
	{
		ASProgram.Class[ASProgram.Multiname] classByName;

		ASProgram.Class[] classObjects = classes.getPreliminaryObjects();
		foreach (c; classObjects)
		{
			assert(!(c.instance.name in classByName), "Duplicate class name " ~ c.instance.name.toString());
			classByName[c.instance.name] = c;
		}

		foreach (c; classObjects)
			foreach (dependency; [c.instance.superName] ~ c.instance.interfaces)
				if (dependency)
					foreach (dependencyName; dependency.toQNames())
					{
						auto pp = dependencyName in classByName;
						if (pp)
							classes.registerDependency(c, *pp);
					}
	}

	this(ASProgram as)
	{
		super(as);
		this.abc = new ABCFile();

		abc.minorVersion = as.minorVersion;
		abc.majorVersion = as.majorVersion;

		super.run();

		registerClassDependencies();

		ints.finalize();
		uints.finalize();
		doubles.finalize();
		strings.finalize();
		namespaces.finalize();
		namespaceSets.finalize();
		multinames.finalize();
		metadatas.finalize();
		classes.finalize();
		methods.finalize();

		abc.ints = ints.values;
		abc.uints = uints.values;
		abc.doubles = doubles.values;
		abc.strings = strings.values;

		abc.namespaces.length = namespaces.values.length;
		foreach (i, v; namespaces.values[1..$])
		{
			auto n = &abc.namespaces[i+1];
			n.kind = v.kind;
			n.name = strings.get(v.name);
		}

		abc.namespaceSets.length = namespaceSets.values.length;
		foreach (i, v; namespaceSets.values[1..$])
		{
			auto n = new uint[v.length];
			foreach (j, ns; v)
				n[j] = namespaces.get(ns);
			abc.namespaceSets[i+1] = n;
		}

		abc.multinames.length = multinames.values.length;
		foreach (i, v; multinames.values[1..$])
		{
			auto n = &abc.multinames[i+1];
			n.kind = v.kind;
			switch (v.kind)
			{
				case ASType.QName:
				case ASType.QNameA:
					n.QName.ns = namespaces.get(v.vQName.ns);
					n.QName.name = strings.get(v.vQName.name);
					break;
				case ASType.RTQName:
				case ASType.RTQNameA:
					n.RTQName.name = strings.get(v.vRTQName.name);
					break;
				case ASType.RTQNameL:
				case ASType.RTQNameLA:
					break;
				case ASType.Multiname:
				case ASType.MultinameA:
					n.Multiname.name = strings.get(v.vMultiname.name);
					n.Multiname.nsSet = namespaceSets.get(v.vMultiname.nsSet);
					break;
				case ASType.MultinameL:
				case ASType.MultinameLA:
					n.MultinameL.nsSet = namespaceSets.get(v.vMultinameL.nsSet);
					break;
				case ASType.TypeName:
					n.TypeName.name = multinames.get(v.vTypeName.name);
					n.TypeName.params.length = v.vTypeName.params.length;
					foreach (j, param; v.vTypeName.params)
						n.TypeName.params[j] = multinames.get(param);
					break;
				default:
					throw new Exception("Unknown Multiname kind");
			}
		}

		abc.metadata.length = metadatas.values.length;
		foreach (i, m; metadatas.values)
		{
			auto n = &abc.metadata[i];
			n.name = strings.get(m.name);
			n.keys.length = m.keys.length;
			foreach (j, key; m.keys)
				n.keys[j] = strings.get(key);
			n.values.length = m.values.length;
			foreach (j, value; m.values)
				n.values[j] = strings.get(value);
		}

		ASProgram.MethodBody[] bodies;

		abc.methods.length = methods.objects.length;
		foreach (i, o; methods.objects)
		{
			auto n = &abc.methods[i];
			n.paramTypes.length = o.paramTypes.length;
			foreach (j, p; o.paramTypes)
				n.paramTypes[j] = multinames.get(p);
			n.returnType = multinames.get(o.returnType);
			n.name = strings.get(o.name);
			n.flags = o.flags;
			n.options.length = o.options.length;
			foreach (j, ref value; o.options)
			{
				n.options[j].kind = value.vkind;
				n.options[j].val = getValueIndex(value);
			}
			n.paramNames.length = o.paramNames.length;
			foreach (j, name; o.paramNames)
				n.paramNames[j] = strings.get(name);

			if (o.vbody)
				bodies ~= o.vbody;
		}

		abc.instances.length = classes.objects.length;
		foreach (i, c; classes.objects)
		{
			auto o = c.instance;
			auto n = &abc.instances[i];

			n.name = multinames.get(o.name);
			n.superName = multinames.get(o.superName);
			n.flags = o.flags;
			n.protectedNs = namespaces.get(o.protectedNs);
			n.interfaces.length = o.interfaces.length;
			foreach (j, intf; o.interfaces)
				n.interfaces[j] = multinames.get(intf);
			n.iinit = methods.get(o.iinit);
			n.traits = convertTraits(o.traits);
		}

		abc.classes.length = classes.objects.length;
		foreach (i, o; classes.objects)
		{
			auto n = &abc.classes[i];
			n.cinit = methods.get(o.cinit);
			n.traits = convertTraits(o.traits);
		}

		abc.scripts.length = as.scripts.length;
		foreach (i, o; as.scripts)
		{
			auto n = &abc.scripts[i];
			n.sinit = methods.get(o.sinit);
			n.traits = convertTraits(o.traits);
		}

		abc.bodies.length = bodies.length;
		foreach (i, o; bodies)
		{
			auto n = &abc.bodies[i];
			n.method = methods.get(o.method);
			n.maxStack = o.maxStack;
			n.localCount = o.localCount;
			n.initScopeDepth = o.initScopeDepth;
			n.maxScopeDepth = o.maxScopeDepth;
			n.instructions.length = o.instructions.length;
			foreach (ii, ref instruction; o.instructions)
				n.instructions[ii] = convertInstruction(instruction);
			n.exceptions.length = o.exceptions.length;
			foreach (j, ref oe; o.exceptions)
			{
				auto ne = &n.exceptions[j];
				ne.from = oe.from;
				ne.to = oe.to;
				ne.target = oe.target;
				ne.excType = multinames.get(oe.excType);
				ne.varName = multinames.get(oe.varName);
			}
			n.traits = convertTraits(o.traits);
		}
	}

	ABCFile.TraitsInfo[] convertTraits(ASProgram.Trait[] traits)
	{
		auto r = new ABCFile.TraitsInfo[traits.length];
		foreach (i, ref trait; traits)
		{
			r[i].name = multinames.get(trait.name);
			r[i].kind = trait.kind;
			r[i].attr = trait.attr;
			switch (trait.kind)
			{
				case TraitKind.Slot:
				case TraitKind.Const:
					r[i].Slot.slotId = trait.vSlot.slotId;
					r[i].Slot.typeName = multinames.get(trait.vSlot.typeName);
					r[i].Slot.vkind = trait.vSlot.value.vkind;
					r[i].Slot.vindex = getValueIndex(trait.vSlot.value);
					break;
				case TraitKind.Class:
					r[i].Class.slotId = trait.vClass.slotId;
					r[i].Class.classi = classes.get(trait.vClass.vclass);
					break;
				case TraitKind.Function:
					r[i].Function.slotId = trait.vFunction.slotId;
					r[i].Function.functioni = methods.get(trait.vFunction.vfunction);
					break;
				case TraitKind.Method:
				case TraitKind.Getter:
				case TraitKind.Setter:
					r[i].Method.dispId = trait.vMethod.dispId;
					r[i].Method.method = methods.get(trait.vMethod.vmethod);
					break;
				default:
					throw new Exception("Unknown trait kind");
			}
			r[i].metadata.length = trait.metadata.length;
			foreach (j, ref m; trait.metadata)
				r[i].metadata[j] = metadatas.get(m);
		}
		return r;
	}

	ABCFile.Instruction convertInstruction(ref ASProgram.Instruction instruction)
	{
		ABCFile.Instruction r;
		r.opcode = instruction.opcode;
		r.arguments.length = instruction.arguments.length;

		foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
			final switch (type)
			{
				case OpcodeArgumentType.Unknown:
					throw new Exception("Don't know how to convert OP_" ~ opcodeInfo[instruction.opcode].name);

				case OpcodeArgumentType.UByteLiteral:
					r.arguments[i].ubytev = instruction.arguments[i].ubytev;
					break;
				case OpcodeArgumentType.IntLiteral:
					r.arguments[i].intv = instruction.arguments[i].intv;
					break;
				case OpcodeArgumentType.UIntLiteral:
					r.arguments[i].uintv = instruction.arguments[i].uintv;
					break;

				case OpcodeArgumentType.Int:
					r.arguments[i].index = ints.get(instruction.arguments[i].intv);
					break;
				case OpcodeArgumentType.UInt:
					r.arguments[i].index = uints.get(instruction.arguments[i].uintv);
					break;
				case OpcodeArgumentType.Double:
					r.arguments[i].index = doubles.get(instruction.arguments[i].doublev);
					break;
				case OpcodeArgumentType.String:
					r.arguments[i].index = strings.get(instruction.arguments[i].stringv);
					break;
				case OpcodeArgumentType.Namespace:
					r.arguments[i].index = namespaces.get(instruction.arguments[i].namespacev);
					break;
				case OpcodeArgumentType.Multiname:
					r.arguments[i].index = multinames.get(instruction.arguments[i].multinamev);
					break;
				case OpcodeArgumentType.Class:
					if (instruction.arguments[i].classv is null)
						r.arguments[i].index = to!uint(abc.classes.length);
					else
						r.arguments[i].index = classes.get(instruction.arguments[i].classv);
					break;
				case OpcodeArgumentType.Method:
					if (instruction.arguments[i].methodv is null)
						r.arguments[i].index = to!uint(abc.methods.length);
					else
						r.arguments[i].index = methods.get(instruction.arguments[i].methodv);
					break;

				case OpcodeArgumentType.JumpTarget:
				case OpcodeArgumentType.SwitchDefaultTarget:
					r.arguments[i].jumpTarget = instruction.arguments[i].jumpTarget;
					break;

				case OpcodeArgumentType.SwitchTargets:
					r.arguments[i].switchTargets = instruction.arguments[i].switchTargets;
					break;
			}
		return r;
	}
}

class ASTraitsVisitor
{
	ASProgram as;

	this(ASProgram as)
	{
		this.as = as;
	}

	void run()
	{
		foreach (ref v; as.scripts)
			visitTraits(v.traits);
	}

	final void visitTraits(ASProgram.Trait[] traits)
	{
		foreach (ref trait; traits)
			visitTrait(trait);
	}

	void visitTrait(ref ASProgram.Trait trait)
	{
		switch (trait.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				break;
			case TraitKind.Class:
				visitTraits(trait.vClass.vclass.traits);
				visitTraits(trait.vClass.vclass.instance.traits);
				break;
			case TraitKind.Function:
				if (trait.vFunction.vfunction.vbody)
					visitTraits(trait.vFunction.vfunction.vbody.traits);
				break;
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				if (trait.vMethod.vmethod.vbody)
					visitTraits(trait.vMethod.vmethod.vbody.traits);
				break;
			default:
				throw new Exception("Unknown trait kind");
		}
	}
}

class ASVisitor : ASTraitsVisitor
{
	this(ASProgram as) { super(as); }

	void visitInt(long) {}
	void visitUint(ulong) {}
	void visitDouble(double) {}
	void visitString(string) {}

	void visitNamespace(ASProgram.Namespace ns)
	{
		if (ns)
			visitString(ns.name);
	}

	void visitNamespaceSet(ASProgram.Namespace[] nsSet)
	{
		foreach (ns; nsSet)
			visitNamespace(ns);
	}

	void visitMultiname(ASProgram.Multiname multiname)
	{
		if (multiname)
			with (multiname)
				switch (kind)
				{
					case ASType.QName:
					case ASType.QNameA:
						visitNamespace(vQName.ns);
						visitString(vQName.name);
						break;
					case ASType.RTQName:
					case ASType.RTQNameA:
						visitString(vRTQName.name);
						break;
					case ASType.RTQNameL:
					case ASType.RTQNameLA:
						break;
					case ASType.Multiname:
					case ASType.MultinameA:
						visitString(vMultiname.name);
						visitNamespaceSet(vMultiname.nsSet);
						break;
					case ASType.MultinameL:
					case ASType.MultinameLA:
						visitNamespaceSet(vMultinameL.nsSet);
						break;
					case ASType.TypeName:
						visitMultiname(vTypeName.name);
						foreach (param; vTypeName.params)
							visitMultiname(param);
						break;
					default:
						throw new .Exception("Unknown Multiname kind");
				}
	}

	void visitScript(ASProgram.Script script)
	{
		if (script)
		{
			visitTraits(script.traits);
			visitMethod(script.sinit);
		}
	}

	override void visitTrait(ref ASProgram.Trait trait)
	{
		visitMultiname(trait.name);
		switch (trait.kind)
		{
			case TraitKind.Slot:
			case TraitKind.Const:
				visitMultiname(trait.vSlot.typeName);
				visitValue(trait.vSlot.value);
				break;
			case TraitKind.Class:
				visitClass(trait.vClass.vclass);
				break;
			case TraitKind.Function:
				visitMethod(trait.vFunction.vfunction);
				break;
			case TraitKind.Method:
			case TraitKind.Getter:
			case TraitKind.Setter:
				visitMethod(trait.vMethod.vmethod);
				break;
			default:
				throw new Exception("Unknown trait kind");
		}
		foreach (metadata; trait.metadata)
			visitMetadata(metadata);
	}

	void visitMetadata(ASProgram.Metadata metadata)
	{
		if (metadata)
		{
			visitString(metadata.name);
			foreach (key; metadata.keys)
				visitString(key);
			foreach (value; metadata.values)
				visitString(value);
		}
	}

	void visitValue(ref ASProgram.Value value)
	{
		switch (value.vkind)
		{
			case ASType.Integer:
				visitInt(value.vint);
				break;
			case ASType.UInteger:
				visitUint(value.vuint);
				break;
			case ASType.Double:
				visitDouble(value.vdouble);
				break;
			case ASType.Utf8:
				visitString(value.vstring);
				break;
			case ASType.Namespace:
			case ASType.PackageNamespace:
			case ASType.PackageInternalNs:
			case ASType.ProtectedNamespace:
			case ASType.ExplicitNamespace:
			case ASType.StaticProtectedNs:
			case ASType.PrivateNamespace:
				visitNamespace(value.vnamespace);
				break;
			case ASType.True:
			case ASType.False:
			case ASType.Null:
			case ASType.Undefined:
				break;
			default:
				throw new Exception("Unknown type");
		}
	}

	void visitClass(ASProgram.Class vclass)
	{
		if (vclass)
		{
			visitMethod(vclass.cinit);
			visitTraits(vclass.traits);

			visitInstance(vclass.instance);
		}
	}

	void visitMethod(ASProgram.Method method)
	{
		if (method)
			with (method)
			{
				foreach (type; paramTypes)
					visitMultiname(type);
				visitMultiname(returnType);
				visitString(name);
				foreach (ref value; options)
					visitValue(value);
				foreach (name; paramNames)
					visitString(name);

				if (vbody)
					visitMethodBody(vbody);
			}
	}

	void visitMethodBody(ASProgram.MethodBody vbody)
	{
		if (vbody)
		{
			foreach (ref instruction; vbody.instructions)
				foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
					final switch (type)
					{
						case OpcodeArgumentType.Unknown:
							throw new Exception("Don't know how to visit OP_" ~ opcodeInfo[instruction.opcode].name);

						case OpcodeArgumentType.UByteLiteral:
						case OpcodeArgumentType.IntLiteral:
						case OpcodeArgumentType.UIntLiteral:
							break;

						case OpcodeArgumentType.Int:
							visitInt(instruction.arguments[i].intv);
							break;
						case OpcodeArgumentType.UInt:
							visitUint(instruction.arguments[i].uintv);
							break;
						case OpcodeArgumentType.Double:
							visitDouble(instruction.arguments[i].doublev);
							break;
						case OpcodeArgumentType.String:
							visitString(instruction.arguments[i].stringv);
							break;
						case OpcodeArgumentType.Namespace:
							visitNamespace(instruction.arguments[i].namespacev);
							break;
						case OpcodeArgumentType.Multiname:
							visitMultiname(instruction.arguments[i].multinamev);
							break;
						case OpcodeArgumentType.Class:
							visitClass(instruction.arguments[i].classv);
							break;
						case OpcodeArgumentType.Method:
							visitMethod(instruction.arguments[i].methodv);
							break;

						case OpcodeArgumentType.JumpTarget:
						case OpcodeArgumentType.SwitchDefaultTarget:
						case OpcodeArgumentType.SwitchTargets:
							break;
					}

			foreach (ref exception; vbody.exceptions)
			{
				visitMultiname(exception.excType);
				visitMultiname(exception.varName);
			}

			visitMethod(vbody.method);
			visitTraits(vbody.traits);
		}
	}

	void visitInstance(ASProgram.Instance instance)
	{
		if (instance)
		{
			visitMultiname(instance.name);
			visitMultiname(instance.superName);
			visitNamespace(instance.protectedNs);
			foreach (intf; instance.interfaces)
				visitMultiname(intf);
			visitMethod(instance.iinit);
			visitTraits(instance.traits);
		}
	}

	override void run()
	{
		foreach (script; as.scripts)
			visitScript(script);
		foreach (vclass; as.orphanClasses)
			visitClass(vclass);
		foreach (method; as.orphanMethods)
			visitMethod(method);
	}
}

private bool contains(T)(T[] arr, T val)
{
	foreach (v; arr)
		if (v == val)
			return true;
	return false;
}

private T checkedGet(T)(T[] array, uint index, T def = T.init)
{
	return index < array.length ? array[index] : def;
}
