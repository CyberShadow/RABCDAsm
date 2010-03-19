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

module disassembler;

import std.file;
import std.string;
import abcfile;
import asprogram;

final class StringBuilder
{
	string buf;
	size_t pos;
	string filename;

	this(string filename)
	{
		this.filename = filename;
		buf.length = 1024;
	}

	void opCatAssign(string s)
	{
		checkIndent();
		auto end = pos + s.length;
		while (buf.length < end)
			buf.length = buf.length*2;
		buf[pos..end] = s;
		pos = end;
	}

	void opCatAssign(char c)
	{
		if (buf.length < pos+1) // speed hack: no loop, no indent check
			buf.length = buf.length*2;
		buf[pos++] = c;
	}

	void save()
	{
		string[] dirSegments = split(filename, "/");
		for (int l=0; l<dirSegments.length-1; l++)
		{
			auto subdir = join(dirSegments[0..l+1], "/");
			if (!exists(subdir))
				mkdir(subdir);
		}
		write(filename, buf[0..pos]);
	}

	int indent;
	bool indented;

	void newLine()
	{
		this ~= '\n';
		indented = false;
	}

	void noIndent()
	{
		indented = true;
	}

	void checkIndent()
	{
		if (!indented)
		{
			for (int i=0; i<indent; i++)
				this ~= ' ';
			indented = true;
		}
	}
}

final class RefBuilder : ASTraitsVisitor
{
	string[void*] objName;
	ASProgram.Class[string] classByName;
	ASProgram.Method[string] methodByName;

	ASProgram.Multiname[] context;
	
	this(ASProgram as)
	{
		super(as);
	}

	override void run()
	{
		foreach (i, ref v; as.scripts)
			addMethod(v.sinit, "script" ~ .toString(i) ~ "_sinit");
		super.run();
	}

	override void visitTrait(ref ASProgram.Trait trait)
	{
		context ~= trait.name;
		switch (trait.kind)
		{
			case TraitKind.Class:
				addClass(trait.vClass.vclass);
				break;
			case TraitKind.Function:
				addMethod(trait.vFunction.vfunction);
				break;
			case TraitKind.Method:
				addMethod(trait.vMethod.vmethod);
				break;
			case TraitKind.Getter:
				addMethod(trait.vMethod.vmethod, "getter");
				break;
			case TraitKind.Setter:
				addMethod(trait.vMethod.vmethod, "setter");
				break;
			default:
				break;
		}
		super.visitTrait(trait);
		context = context[0..$-1];
	}

	string contextToString(string field)
	{
		string[] strings = new string[context.length + (field ? 1 : 0)];
		foreach (i, m; context)
		{
			// should this check ever fail, it's easy to fix it - just build any unique-ish string from the context
			if (m.kind != ASType.QName)
				throw new Exception("Trait name is not a QName");
			strings[i] = (m.vQName.ns.name.length ? m.vQName.ns.name ~ "." : "") ~ m.vQName.name;
		}
		if (field)
			strings[$-1] = field;
		string s = join(strings, "/");
		foreach (ref c; s)
			if (c < 0x20 || c == '"')
				c = '_';
		return s;
	}

	string addObject(T)(T obj, ref T[string] objByName, string field)
	{
		auto name = contextToString(field);
		auto uniqueName = name;
		int i = 1;
		while (uniqueName in objByName)
			uniqueName = name ~ "_" ~ .toString(++i);
		objByName[uniqueName] = obj;
		objName[cast(void*)obj] = uniqueName;
		return uniqueName;
	}

	void addClass(ASProgram.Class vclass)
	{
		addObject(vclass, classByName, string.init);
		addMethod(vclass.cinit, "cinit");
		addMethod(vclass.instance.iinit, "iinit");
	}

	void addMethod(ASProgram.Method method, string field = null)
	{
		addObject(method, methodByName, field);
	}

	string getObjectName(T)(T obj, ref T[string] objByName)
	{
		auto pname = cast(void*)obj in objName;
		if (pname)
			return *pname;
		else
			return addObject(obj, objByName, "orphan");
	}

	string getClassName(ASProgram.Class vclass)
	{
		return getObjectName(vclass, classByName);
	}

	string getMethodName(ASProgram.Method method)
	{
		return getObjectName(method, methodByName);
	}
}

final class Disassembler
{
	ASProgram as;
	string name;
	RefBuilder refs;

	version (Windows)
		string[string] filenameMappings;
	
	this(ASProgram as, string name)
	{
		this.as = as;
		this.name = name;
	}

	void disassemble()
	{
		refs = new RefBuilder(as);
		refs.run();
		
		StringBuilder sb = new StringBuilder(name ~ "/" ~ name ~ ".main.asasm");
		
		sb ~= "program";
		sb.indent++; sb.newLine();

		sb ~= "minorversion ";
		sb ~= .toString(as.minorVersion);
		sb.newLine();
		sb ~= "majorversion ";
		sb ~= .toString(as.majorVersion);
		sb.newLine();
		sb.newLine();
		
		foreach (i, script; as.scripts)
		{
			dumpScript(sb, script, i);
			sb.newLine();
		}
		
		if (as.orphanClasses.length)
		{
			sb.newLine();
			sb ~= "; ===========================================================================";
			sb.newLine();
			sb.newLine();

			foreach (i, vclass; as.orphanClasses)
			{
				sb ~= "class";
				dumpClass(sb, vclass);
				sb.newLine();
			}
		}

		if (as.orphanMethods.length)
		{
			sb.newLine();
			sb ~= "; ===========================================================================";
			sb.newLine();
			sb.newLine();

			foreach (i, method; as.orphanMethods)
			{
				sb ~= "method";
				dumpMethod(sb, method);
				sb.newLine();
			}
		}

		sb.indent--;
		sb ~= "end ; program"; sb.newLine();

		sb.save();
	}

	void dumpInt(StringBuilder sb, long v)
	{
		if (v == ABCFile.NULL_INT)
			sb ~= "null";
		else
			sb ~= .toString(v);
	}

	void dumpUInt(StringBuilder sb, ulong v)
	{
		if (v == ABCFile.NULL_UINT)
			sb ~= "null";
		else
			sb ~= .toString(v);
	}

	void dumpDouble(StringBuilder sb, double v)
	{
		sb ~= .toString(v);
	}

	void dumpString(StringBuilder sb, string str)
	{
		if (str is null)
			sb ~= "null";
		else
		{
			static const char[16] hexDigits = "0123456789ABCDEF";
		
			sb ~= '"';
			foreach (c; str)
				if (c == 0x0A)
					sb ~= `\n`;
				else
				if (c == 0x0D)
					sb ~= `\r`;
				else
				if (c == '\\')
					sb ~= `\\`;
				else
				if (c == '"')
					sb ~= `\"`;
				else
				if (c < 0x20)
				{
					sb ~= `\x`;
					sb ~= hexDigits[c / 0x10];
					sb ~= hexDigits[c % 0x10];
				}
				else
					sb ~= c;
			sb ~= '"';
		}
	}

	void dumpNamespace(StringBuilder sb, ASProgram.Namespace namespace)
	{
		if (namespace is null)
			sb ~= "null";
		else
		with (namespace)
		{
			sb ~= ASTypeNames[kind];
			sb ~= '(';
			dumpString(sb, name);
			if (kind == ASType.PrivateNamespace)
			{
				sb ~= ", ";
				dumpUInt(sb, privateIndex);
			}
			sb ~= ')';
		}
	}

	void dumpNamespaceSet(StringBuilder sb, ASProgram.Namespace[] set)
	{
		if (set is null)
			sb ~= "null";
		else
		sb ~= '[';
		foreach (i, ns; set)
		{
			dumpNamespace(sb, ns);
			if (i < set.length-1)
				sb ~= ", ";
		}
		sb ~= ']';
	}

	void dumpMultiname(StringBuilder sb, ASProgram.Multiname multiname)
	{
		if (multiname is null)
			sb ~= "null";
		else
		with (multiname)
		{
			sb ~= ASTypeNames[kind];
			sb ~= '(';
			switch (kind)
			{
				case ASType.QName:
				case ASType.QNameA:
					dumpNamespace(sb, vQName.ns);
					sb ~= ", ";
					dumpString(sb, vQName.name);
					break;
				case ASType.RTQName:
				case ASType.RTQNameA:
					dumpString(sb, vRTQName.name);
					break;
				case ASType.RTQNameL:
				case ASType.RTQNameLA:
					break;
				case ASType.Multiname:
				case ASType.MultinameA:
					dumpString(sb, vMultiname.name);
					sb ~= ", ";
					dumpNamespaceSet(sb, vMultiname.nsSet);
					break;
				case ASType.MultinameL:
				case ASType.MultinameLA:
					dumpNamespaceSet(sb, vMultinameL.nsSet);
					break;
				case ASType.TypeName:
					dumpMultiname(sb, vTypeName.name);
					sb ~= '<';
					foreach (i, param; vTypeName.params)
					{
						dumpMultiname(sb, param);
						if (i < vTypeName.params.length-1)
							sb ~= ", ";
					}
					sb ~= '>';
					break;
				default:
					throw new .Exception("Unknown Multiname kind");
			}
			sb ~= ')';
		}
	}

	void dumpTraits(StringBuilder sb, ASProgram.Trait[] traits)
	{
		foreach (ref trait; traits)
		{
			sb ~= "trait ";
			static const string[] TraitKindNames = ["slot", "method", "getter", "setter", "class", "function", "const"];
			sb ~= TraitKindNames[trait.kind];
			sb ~= ' ';
			dumpMultiname(sb, trait.name);
			switch (trait.kind)
			{
				case TraitKind.Slot:
				case TraitKind.Const:
					if (trait.vSlot.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vSlot.slotId);
					}
					if (trait.vSlot.typeName)
					{
						sb ~= " type ";
						dumpMultiname(sb, trait.vSlot.typeName);
					}
					if (trait.vSlot.value.vkind)
					{
						sb ~= " value ";
						dumpValue(sb, trait.vSlot.value);
					}
					sb ~= " end";
					sb.newLine();
					break;
				case TraitKind.Class:
					if (trait.vClass.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vClass.slotId);
					}
					sb.indent++; sb.newLine();
					sb ~= "class";
					dumpClass(sb, trait.vClass.vclass);
					sb.indent--; sb ~= "end ; trait"; sb.newLine();
					break;
				case TraitKind.Function:
					if (trait.vFunction.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vFunction.slotId);
					}
					sb.indent++; sb.newLine();
					sb ~= "method";
					dumpMethod(sb, trait.vFunction.vfunction);
					sb.indent--; sb ~= "end ; trait"; sb.newLine();
					break;
				case TraitKind.Method:
				case TraitKind.Getter:
				case TraitKind.Setter:
					if (trait.vMethod.dispId)
					{
						sb ~= " dispid ";
						dumpUInt(sb, trait.vMethod.dispId);
					}
					sb.indent++; sb.newLine();
					sb ~= "method";
					dumpMethod(sb, trait.vMethod.vmethod);
					sb.indent--; sb ~= "end ; trait"; sb.newLine();
					break;
				default:
					throw new Exception("Unknown trait kind");
			}
		}
	}

	void dumpFlags(StringBuilder sb, ubyte flags, string[] names)
	{
		assert(names.length == 8);
		for (int i=0; flags; i++, flags>>=1)
			if (flags & 1)
			{
				sb ~= "flag ";
				sb ~= names[i];
				sb.newLine();
			}
	}

	void dumpValue(StringBuilder sb, ref ASProgram.Value value)
	{
		with (value)
		{
			sb ~= ASTypeNames[vkind];
			sb ~= '(';
			switch (vkind)
			{
				case ASType.Integer:
					dumpInt(sb, vint);
					break;
				case ASType.UInteger:
					dumpUInt(sb, vuint);
					break;
				case ASType.Double:
					dumpDouble(sb, vdouble);
					break;
				case ASType.Utf8:
					dumpString(sb, vstring);
					break;
				case ASType.Namespace:
				case ASType.PackageNamespace:
				case ASType.PackageInternalNs:
				case ASType.ProtectedNamespace:
				case ASType.ExplicitNamespace:
				case ASType.StaticProtectedNs:
				case ASType.PrivateNamespace:
					dumpNamespace(sb, vnamespace);
					break;
				case ASType.True:
				case ASType.False:
				case ASType.Null:
				case ASType.Undefined:
					break;
				default:
					throw new Exception("Unknown type");
			}

			sb ~= ')';
		}
	}

	void dumpMethod(StringBuilder sb, ASProgram.Method method)
	{
		sb.indent++; sb.newLine();
		if (method.name !is null)
		{
			sb ~= "name ";
			dumpString(sb, method.name);
			sb.newLine();
		}
		auto refName = cast(void*)method in refs.objName;
		if (refName)
		{
			sb ~= "refid ";
			dumpString(sb, *refName);
			sb.newLine();
		}
		foreach (m; method.paramTypes)
		{
			sb ~= "param ";
			dumpMultiname(sb, m);
			sb.newLine();
		}
		if (method.returnType)
		{
			sb ~= "returns ";
			dumpMultiname(sb, method.returnType);
			sb.newLine();
		}
		dumpFlags(sb, method.flags, MethodFlagNames);
		foreach (ref v; method.options)
		{
			sb ~= "optional ";
			dumpValue(sb, v);
			sb.newLine();
		}
		foreach (s; method.paramNames)
		{
			sb ~= "paramname ";
			dumpString(sb, s);
			sb.newLine();
		}
		if (method.vbody)
			dumpMethodBody(sb, method.vbody);
		sb.indent--; sb ~= "end ; method"; sb.newLine();
	}

	string toFileName(string refid)
	{
		string filename = refid.dup;
		foreach (ref c; filename)
			if (c == '.')
				c = '/';
			else
			if (c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|')
				c = '_';
		
		version (Windows)
		{
			string[] dirSegments = split(filename, "/");
			for (int l=0; l<dirSegments.length-1; l++)
			{
			again:	
				string subdir = join(dirSegments[0..l+1], "/");
				string subdirl = tolower(subdir);
				string* canonicalp = subdirl in filenameMappings;
				if (canonicalp && *canonicalp != subdir)
				{
					dirSegments[l] = dirSegments[l] ~ "_"; // not ~=
					goto again;
				}
				filenameMappings[subdirl] = subdir;
			}
			filename = join(dirSegments, "/");
		}
		
		return filename ~ ".asasm";
	}

	void dumpClass(StringBuilder mainsb, ASProgram.Class vclass)
	{
		if (mainsb.filename.split("/").length != 2)
			throw new Exception("TODO: nested classes");
		auto refName = cast(void*)vclass in refs.objName;
		auto filename = toFileName(refs.getClassName(vclass));
		StringBuilder sb = new StringBuilder(name ~ "/" ~ filename);
		if (refName)
		{
			sb ~= "refid ";
			dumpString(sb, *refName);
			sb.newLine();
		}
		sb ~= "instance ";
		dumpInstance(sb, vclass.instance);
		sb ~= "cinit "; dumpMethod(sb, vclass.cinit);
		dumpTraits(sb, vclass.traits);
		
		sb.save();

		mainsb.indent++; mainsb.newLine();
		mainsb ~= "#include ";
		dumpString(mainsb, filename);
		mainsb.newLine();
		mainsb.indent--; mainsb ~= "end ; class"; mainsb.newLine();
	}

	void dumpInstance(StringBuilder sb, ASProgram.Instance instance)
	{
		dumpMultiname(sb, instance.name);
		sb.indent++; sb.newLine();
		if (instance.superName)
		{
			sb ~= "extends ";
			dumpMultiname(sb, instance.superName);
			sb.newLine();
		}
		foreach (i; instance.interfaces)
		{
			sb ~= "implements ";
			dumpMultiname(sb, i);
			sb.newLine();
		}
		dumpFlags(sb, instance.flags, InstanceFlagNames);
		if (instance.protectedNs)
		{
			sb ~= "protectedns ";
			dumpNamespace(sb, instance.protectedNs);
			sb.newLine();
		}
		sb ~= "iinit "; dumpMethod(sb, instance.iinit);
		dumpTraits(sb, instance.traits);
		sb.indent--; sb ~= "end ; instance"; sb.newLine();
	}

	void dumpScript(StringBuilder sb, ASProgram.Script script, uint index)
	{
		sb ~= "script ; ";
		sb ~= .toString(index);
		sb.indent++; sb.newLine();
		sb ~= "sinit "; dumpMethod(sb, script.sinit);
		dumpTraits(sb, script.traits);
		sb.indent--; sb ~= "end ; script"; sb.newLine();
	}

	void dumpUIntField(StringBuilder sb, string name, uint value)
	{
		sb ~= name;
		sb ~= ' ';
		dumpUInt(sb, value);
		sb.newLine();
	}

	void dumpMethodBody(StringBuilder sb, ASProgram.MethodBody mbody)
	{
		sb ~= "body";
		sb.indent++; sb.newLine();
		dumpUIntField(sb, "maxstack", mbody.maxStack);
		dumpUIntField(sb, "localcount", mbody.localCount);
		dumpUIntField(sb, "initscopedepth", mbody.initScopeDepth);
		dumpUIntField(sb, "maxscopedepth", mbody.maxScopeDepth);
		sb ~= "code";
		sb.newLine();

		bool[] labels = new bool[mbody.instructions.length];
		// reserve exception labels
		foreach (ref e; mbody.exceptions)
			labels[e.from] = labels[e.to] = labels[e.target] = true;
		dumpInstructions(sb, mbody.instructions, labels);

		sb ~= "end ; code";
		sb.newLine();
		foreach (ref e; mbody.exceptions)
		{
			sb ~= "try from L";
			sb ~= .toString(e.from);
			sb ~= " to L";
			sb ~= .toString(e.to);
			sb ~= " target L";
			sb ~= .toString(e.target);
			sb ~= " type ";
			dumpMultiname(sb, e.excType);
			sb ~= " name ";
			dumpMultiname(sb, e.varName);
			sb ~= " end";
			sb.newLine();
		}
		sb.indent--; sb ~= "end ; body"; sb.newLine();
	}

	void dumpInstructions(StringBuilder sb, ASProgram.Instruction[] instructions, bool[] labels)
	{
		sb.indent++;
		foreach (ref instruction; instructions)
			foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
				switch (type)
				{
					case OpcodeArgumentType.JumpTarget:
					case OpcodeArgumentType.SwitchDefaultTarget:
						labels[instruction.arguments[i].jumpTarget] = true;
						break;
					case OpcodeArgumentType.SwitchTargets:
						foreach (ref x; instruction.arguments[i].switchTargets)
							labels[x] = true;
						break;
					default:
						break;
				}
		foreach (ii, ref instruction; instructions)
		{
			if (labels[ii])
			{
				sb.noIndent();
				sb ~= 'L';
				sb ~= .toString(ii);
				sb ~= ':';
				sb.newLine();
			}

			sb ~= opcodeInfo[instruction.opcode].name;
			bool extraNewLine = false;
			auto argTypes = opcodeInfo[instruction.opcode].argumentTypes;
			if (argTypes.length)
			{
				for (int i=opcodeInfo[instruction.opcode].name.length; i<20; i++)
					sb ~= ' ';
				foreach (i, type; argTypes)
				{
					switch (type)
					{
						case OpcodeArgumentType.Unknown:
							throw new Exception("Don't know how to disassemble OP_" ~ opcodeInfo[instruction.opcode].name);

						case OpcodeArgumentType.UByteLiteral:
							sb ~= .toString(instruction.arguments[i].ubytev);
							break;
						case OpcodeArgumentType.UIntLiteral:
							sb ~= .toString(instruction.arguments[i].uintv);
							break;

						case OpcodeArgumentType.Int:
							dumpInt(sb, instruction.arguments[i].intv);
							break;
						case OpcodeArgumentType.UInt:
							dumpUInt(sb, instruction.arguments[i].uintv);
							break;
						case OpcodeArgumentType.Double:
							dumpDouble(sb, instruction.arguments[i].doublev);
							break;
						case OpcodeArgumentType.String:
							dumpString(sb, instruction.arguments[i].stringv);
							break;
						case OpcodeArgumentType.Namespace:
							dumpNamespace(sb, instruction.arguments[i].namespacev);
							break;
						case OpcodeArgumentType.Multiname:
							dumpMultiname(sb, instruction.arguments[i].multinamev);
							break;
						case OpcodeArgumentType.Class:
							dumpString(sb, refs.getClassName(instruction.arguments[i].classv));
							break;
						case OpcodeArgumentType.Method:
							dumpString(sb, refs.getMethodName(instruction.arguments[i].methodv));
							break;

						case OpcodeArgumentType.JumpTarget:
						case OpcodeArgumentType.SwitchDefaultTarget:
							sb ~= 'L';
							sb ~= .toString(instruction.arguments[i].jumpTarget);
							extraNewLine = true;
							break;

						case OpcodeArgumentType.SwitchTargets:
							sb ~= '[';
							auto targets = instruction.arguments[i].switchTargets;
							foreach (ti, t; targets)
							{
								sb ~= 'L';
								sb ~= .toString(t);
								if (ti < targets.length-1)
									sb ~= ", ";
							}
							sb ~= ']';
							break;
					
						default:
							assert(0);
					}
					if (i < argTypes.length-1)
						sb ~= ", ";
				}
			}
			sb.newLine();
			if (extraNewLine)
				sb.newLine();
		}
		sb.indent--;
	}
}
