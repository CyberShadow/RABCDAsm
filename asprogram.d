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

module asprogram;

import abcfile;

/** 
 * Represents a hierarchically-organized ActionScript program,
 * with all constants expanded and bytecode disassembled to separate instructions.
 */

class ASProgram
{
	ushort minorVersion, majorVersion;
	Script[] scripts;

	static class Namespace
	{
		ASType kind;
		string name;
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
	}

	static class Method
	{
		Multiname[] paramTypes;
		Multiname returnType;
		string name;
		ubyte flags; // MethodFlags bitmask
		Value[] options;
		string[] paramNames;

		MethodBody vbody;
	}

	static class Metadata
	{
		struct Item
		{
			string key, value;
		}

		string name;
		Item[] items;
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
			int vint;             // Integer
			uint vuint;           // UInteger
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
	}

	static class Script
	{
		Method init;
		Trait[] traits;
	}

	static class MethodBody
	{
		Method method;
		uint maxStack;
		uint localCount;
		uint initScopeDepth;
		uint maxScopeDepth;
		Instruction[] code;
		Exception[] exceptions;
		Trait[] traits;
	}

	struct Instruction
	{
		ubyte opcode;
	}
	
	struct Exception
	{
		uint from, to, target;
		string excType;
		string varName;
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

class ABCtoAS
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
	ASProgram.MethodBody[] bodies;
	
	ASProgram.Value convertValue(ASType kind, uint val)
	{
		ASProgram.Value o;
		o.vkind = kind;
		switch (o.vkind)
		{
			case ASType.Integer:
				o.vint = cast(int)abc.ints[val]; // WARNING: discarding extra bits
				break;
			case ASType.UInteger:
				o.vuint = cast(uint)abc.uints[val]; // WARNING: discarding extra bits
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
		
	this(ABCFile abc)
	{
		this.as = new ASProgram();
		this.abc = abc;
		
		as.minorVersion = abc.minorVersion;
		as.majorVersion = abc.majorVersion;

		namespaces.length = abc.namespaces.length;
		foreach (i, ref namespace; abc.namespaces)
			if (i)
			{
				auto n = new ASProgram.Namespace();
				n.kind = namespace.kind;
				n.name = abc.strings[namespace.name];
				namespaces[i] = n;
			}

		namespaceSets.length = abc.namespaceSets.length;
		foreach (i, ref namespaceSet; abc.namespaceSets)
			if (i)
			{
				auto n = new ASProgram.Namespace[namespaceSet.length];
				foreach (j, namespace; namespaceSet)
					n[j] = namespaces[namespace];
				namespaceSets[i] = n;
			}

		multinames.length = abc.multinames.length;
		foreach (i, ref multiname; abc.multinames)
			if (i)
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
						if (multiname.TypeName.name > i)
							throw new Exception("Forward Multiname/TypeName reference");
						n.vTypeName.name = multinames[multiname.TypeName.name];
						n.vTypeName.params.length = multiname.TypeName.params.length;
						foreach (j, param; multiname.TypeName.params)
						{
							if (param > i)
								throw new Exception("Forward Multiname/TypeName parameter reference");
							n.vTypeName.params[j] = multinames[param];
						}
						break;
					default:
						throw new Exception("Unknown Multiname kind");
				}
				
				multinames[i] = n;
			}

		methods.length = abc.methods.length;
		foreach (i, ref method; abc.methods)
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
			methods[i] = n;
		}

		metadata.length = abc.metadata.length;
		foreach (i, ref md; abc.metadata)
		{
			auto n = new ASProgram.Metadata();
			n.name = abc.strings[md.name];
			n.items.length = md.items.length;
			foreach (j, ref item; md.items)
			{
				n.items[j].key = abc.strings[item.key];
				n.items[j].value = abc.strings[item.value];
			}
			metadata[i] = n;
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
						r[i].vClass.vclass = classes[trait.Class.classi];
						break;
					case TraitKind.Function:
						r[i].vFunction.slotId = trait.Function.slotId;
						r[i].vFunction.vfunction = methods[trait.Function.functioni];
						break;
					case TraitKind.Method:
					case TraitKind.Getter:
					case TraitKind.Setter:
						r[i].vMethod.dispId = trait.Method.dispId;
						r[i].vMethod.vmethod = methods[trait.Method.method];
						break;
					default:
						throw new Exception("Unknown trait kind");
				}
			}
			return r;
		}

		instances.length = abc.instances.length;
		foreach (i, ref instance; abc.instances)
		{
			auto n = new ASProgram.Instance();
			n.name = multinames[instance.name];
			n.superName = multinames[instance.superName];
			n.flags = instance.flags;
			n.protectedNs = namespaces[instance.protectedNs];
			n.interfaces.length = instance.interfaces.length;
			foreach (j, intf; instance.interfaces)
				n.interfaces[j] = multinames[intf];
			n.iinit = methods[instance.iinit];
			n.traits = convertTraits(instance.traits);
			instances[i] = n;
		}

		classes.length = abc.classes.length;
		foreach (i, ref vclass; abc.classes)
		{
			auto n = new ASProgram.Class();
			n.cinit = methods[vclass.cinit];
			n.traits = convertTraits(vclass.traits);
			n.instance = instances[i];
			classes[i] = n;
		}

		as.scripts.length = abc.scripts.length;
		foreach (i, ref script; abc.scripts)
		{
			auto n = new ASProgram.Script;
			n.init = methods[script.init];
			n.traits = convertTraits(script.traits);
			as.scripts[i] = n;
		}

		foreach (i, ref vbody; abc.bodies)
		{
			auto n = new ASProgram.MethodBody;
			n.method = methods[vbody.method];
			n.maxStack = vbody.maxStack;
			n.localCount = vbody.localCount;
			n.initScopeDepth = vbody.initScopeDepth;
			n.maxScopeDepth= vbody.maxScopeDepth;
			n.code = disassemble(vbody.code);
			n.exceptions.length = vbody.exceptions.length;
			foreach (j, ref exc; vbody.exceptions)
			{
				auto e = &n.exceptions[j];
				e.from = exc.from;
				e.to = exc.to;
				e.target = exc.target;
				e.excType = abc.strings[exc.excType];
				e.varName = abc.strings[exc.varName];
			}
			n.traits = convertTraits(vbody.traits);

			n.method.vbody = n;
		}
	}

	ASProgram.Instruction[] disassemble(ubyte[] code)
	{
		return null;
	}
}

class AStoABC
{
	ABCFile abc;
	ASProgram as;
	
	this(ASProgram as)
	{
		this.abc = new ABCFile();
		this.as = as;
		
		abc.minorVersion = as.minorVersion;
		abc.majorVersion = as.majorVersion;

		// ...
	}
}
