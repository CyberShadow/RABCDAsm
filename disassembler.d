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

struct StringBuilder
{
	string buf;
	size_t pos;
	void opCatAssign(string s)
	{
		checkIndent();
		auto end = pos + s.length;
		while (buf.length < end)
			buf.length = buf.length==0 ? 1024 : buf.length*2;
		buf[pos..end] = s;
		pos = end;
	}

	void opCatAssign(char c)
	{
		if (buf.length < pos+1) // hack: no loop, no 0-length check
			buf.length = buf.length*2;
		buf[pos++] = c;
	}

	string toString()
	{
		return buf[0..pos];
	}

	int indent;
	bool indented;

	void newLine()
	{
		*this ~= '\n';
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
				*this ~= ' ';
			indented = true;
		}
	}
}

class Disassembler
{
	ASProgram as;
	string name;
	
	this(ASProgram as, string name)
	{
		this.as = as;
		this.name = name;
	}

final:
	void disassemble()
	{
		if (!exists(name))
			mkdir(name);
		
		StringBuilder sb;
		foreach (i, script; as.scripts)
		{
			dumpScript(sb, script, i);
			sb.newLine();
		}
		write(name ~ "/" ~ name ~ ".asasm", sb.toString);
	}

	void dumpInt(ref StringBuilder sb, long v)
	{
		if (v == ABCFile.NULL_INT)
			sb ~= "null";
		else
			sb ~= .toString(v);
	}

	void dumpUInt(ref StringBuilder sb, ulong v)
	{
		if (v == ABCFile.NULL_UINT)
			sb ~= "null";
		else
			sb ~= .toString(v);
	}

	void dumpDouble(ref StringBuilder sb, double v)
	{
		sb ~= .toString(v);
	}

	void dumpString(ref StringBuilder sb, string str)
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
				if (c == '\\')
					sb ~= `\\`;
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

	void dumpNamespace(ref StringBuilder sb, ASProgram.Namespace namespace)
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

	void dumpNamespaceSet(ref StringBuilder sb, ASProgram.Namespace[] set)
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

	void dumpMultiname(ref StringBuilder sb, ASProgram.Multiname multiname)
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

	void dumpTraits(ref StringBuilder sb, ASProgram.Trait[] traits)
	{
		foreach (ref trait; traits)
		{
			sb ~= "trait ";
			static const string[] TraitKindNames = ["slot", "method", "getter", "setter", "class", "function", "const"];
			sb ~= TraitKindNames[trait.kind];
			sb ~= ' ';
			dumpMultiname(sb, trait.name);
			sb ~= ' ';
			switch (trait.kind)
			{
				case TraitKind.Slot:
				case TraitKind.Const:
					dumpUInt(sb, trait.vSlot.slotId);
					sb ~= ' ';
					dumpMultiname(sb, trait.vSlot.typeName);
					sb ~= ' ';
					dumpValue(sb, trait.vSlot.value);
					sb.newLine();
					break;
				case TraitKind.Class:
					dumpUInt(sb, trait.vSlot.slotId);
					dumpClass(sb, trait.vClass.vclass);
					break;
				case TraitKind.Function:
					dumpUInt(sb, trait.vSlot.slotId);
					dumpMethod(sb, trait.vFunction.vfunction);
					break;
				case TraitKind.Method:
				case TraitKind.Getter:
				case TraitKind.Setter:
					dumpUInt(sb, trait.vMethod.dispId);
					dumpMethod(sb, trait.vMethod.vmethod);
					break;
				default:
					throw new Exception("Unknown trait kind");
			}
		}
	}

	void dumpFlags(ref StringBuilder sb, ubyte flags, string[] names)
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

	void dumpValue(ref StringBuilder sb, ref ASProgram.Value value)
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

	void dumpMethod(ref StringBuilder sb, ASProgram.Method method)
	{
		sb.indent++; sb.newLine();
		if (method.name !is null)
		{
			sb ~= "name ";
			dumpString(sb, method.name);
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

	void dumpClass(ref StringBuilder sb, ASProgram.Class vclass)
	{
		sb.indent++; sb.newLine();
		sb ~= "instance ";
		dumpInstance(sb, vclass.instance);
		sb ~= "cinit "; dumpMethod(sb, vclass.cinit);
		dumpTraits(sb, vclass.traits);
		sb.indent--; sb ~= "end ; class"; sb.newLine();
	}

	void dumpInstance(ref StringBuilder sb, ASProgram.Instance instance)
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

	void dumpScript(ref StringBuilder sb, ASProgram.Script script, uint index)
	{
		sb ~= "script ; ";
		sb ~= .toString(index);
		sb.indent++; sb.newLine();
		sb ~= "sinit "; dumpMethod(sb, script.sinit);
		dumpTraits(sb, script.traits);
		sb.indent--; sb ~= "end ; script"; sb.newLine();
	}

	void dumpUIntField(ref StringBuilder sb, string name, uint value)
	{
		sb ~= name;
		sb ~= ' ';
		dumpUInt(sb, value);
		sb.newLine();
	}

	void dumpMethodBody(ref StringBuilder sb, ASProgram.MethodBody mbody)
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

	void dumpInstructions(ref StringBuilder sb, ASProgram.Instruction[] instructions, bool[] labels)
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
							//r.arguments[i].index = ClassR.get(instruction.arguments[i].classv);
							sb ~= "<class>";
							break;
						case OpcodeArgumentType.Method:
							//r.arguments[i].index = MethodR.get(instruction.arguments[i].methodv);
							sb ~= "<method>";
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
