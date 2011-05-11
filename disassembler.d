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
import std.conv;
import std.exception;
import std.algorithm;
import abcfile;
import asprogram;
import autodata;

final class StringBuilder
{
	char[] buf;
	size_t pos;
	string filename;

	this(string filename)
	{
		if (exists(filename))
			throw new Exception(filename ~ " exists");
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
	struct ContextItem
	{
		enum Type { Multiname, String }
		Type type;

		union
		{
			ASProgram.Multiname multiname;
			struct
			{
				string str;
				bool filenameSuffix;
			}
		}

		struct Segment
		{
			char delim;
			string str;
		}

		Segment[] toSegments(bool filename)
		{
			final switch(type)
			{
			case Type.Multiname:
				assert(multiname.kind == ASType.QName);
				if (multiname.vQName.ns.kind == ASType.PrivateNamespace)
					throw new Exception("Stringifying unexpanded context");

				auto nsName = multiname.vQName.ns.name;
				if (nsName.length)
					if (multiname.vQName.name.length)
						return [Segment('/', nsName), Segment(filename ? '/' : ':', multiname.vQName.name)];
					else
						return [Segment('/', nsName)];
				else
					if (multiname.vQName.name.length)
						return [Segment('/', multiname.vQName.name)];
					else
						assert(0);
			case Type.String:
				return [Segment(filenameSuffix ? '.' : '/', str)];
			}
		}

		static ContextItem[] expand(RefBuilder refs, ContextItem[] context, bool noThrow) /// recursively expand all private namespaces
		{
			ContextItem[] newContext;
			foreach (ref c; context)
			{
				auto cEx = c.expand(refs, noThrow);
				if (cEx is null) return null;
				newContext ~= cEx;
			}
			return newContext;
		}

		ContextItem[] expand(RefBuilder refs, bool noThrow)
		{
			if (type==Type.Multiname && multiname.vQName.ns.kind == ASType.PrivateNamespace)
			{
				auto pcontext = multiname.vQName.ns.privateIndex in refs.privateNamespaces.contexts;
				if (pcontext is null)
					if (noThrow)
						return null;
					else
						throw new Exception("Expanding unknown private namespace " ~ to!string(multiname.vQName.ns.privateIndex));
				auto expanded = expand(refs, *pcontext, noThrow);
				if (expanded is null) return null;
				return expanded ~ (multiname.vQName.name.length ? [ContextItem(multiname.vQName.name)] : null); // hack
			}
			else
				return (&this)[0..1];
		}

		this(ASProgram.Multiname m)
		{
			this.type = Type.Multiname;
			this.multiname = m;
		}

		this(string s, bool filenameSuffix = false)
		{
			this.type = Type.String;
			this.str = s;
			this.filenameSuffix = filenameSuffix;
		}

		mixin AutoCompare;
		mixin AutoToString;

		R processData(R, string prolog, string epilog, H)(ref H handler) const
		{
			mixin(prolog);
			mixin(addAutoField("type"));
			final switch (type)
			{
			case Type.Multiname:
				mixin(addAutoField("multiname"));
				break;
			case Type.String:
				mixin(addAutoField("str"));
				mixin(addAutoField("filenameSuffix"));
				break;
			}
			mixin(epilog);
		}
	}

	ContextItem[] context; // potential optimization: use array-based stack

	void pushContext(T...)(T v) { context ~= ContextItem(v); }
	void popContext() { context = context[0..$-1]; }

	struct ContextSet(T, bool ALLOW_DUPLICATES)
	{
		ContextItem[][T] contexts;
		string[T] names, filenames;

		void add(U)(U obj, ContextItem[] context)
		{
			auto p = cast(T)obj;
			static if (ALLOW_DUPLICATES)
			{
				auto pexisting = p in contexts;
				if (pexisting)
				{
					auto rootContext = contextRoot(*pexisting, context);
					enforce(rootContext.length, format("Can't find common private namespace root between ", *pexisting, " and ", context));
					contexts[p] = rootContext;
				}
				else
					contexts[p] = context;
			}
			else
			{
				enforce(p !in contexts, format("Duplicate object reference: ", contexts[p], " and ", context));
				contexts[p] = context.dup;
			}
		}

		void coagulate(RefBuilder refs)
		{
			int[string] collisionCounter;
			T[string] first;

			foreach (obj; contexts.keys.sort)
			{
				auto context = contexts[obj];
				auto bname = refs.contextToString(context, false);
				auto bfilename = refs.contextToString(context, true);
				auto pcounter = bname in collisionCounter;
				int counter = pcounter ? *pcounter : 0;
				if (counter==1)
				{
					auto firstObj = first[bname];
					names[firstObj] ~= "#0";
					filenames[firstObj] ~= "#0";
				}

				string suffix;
				if (counter==0)
					first[bname] = cast(T)obj;
				else
					suffix = '#' ~ to!string(counter);
				names[obj] = bname ~ suffix;
				filenames[obj] = bfilename ~ suffix;
				collisionCounter[bname] = counter+1;
			}
		}

		bool isAdded(U)(U obj) { return (cast(T)obj in contexts) ? true : false; }
		ContextItem[] getContext(U)(U obj) { return contexts[cast(T)obj]; }

		string getName(U)(U obj)
		{
			auto pname = cast(T)obj in names;
			assert(pname, format("Unscanned object: ", obj));
			return *pname;
		}

		version (Windows)
			static string[string] filenameMappings;

		string getFilename(U)(U obj)
		{
			auto pname = cast(T)obj in filenames;
			assert(pname, format("Unscanned object: ", obj));
			auto filename = *pname;

			version (Windows)
			{
				string[] dirSegments = split(filename, "/");
				for (int l=0; l<dirSegments.length; l++)
				{
				again:
					string subpath = join(dirSegments[0..l+1], "/");
					string subpathl = tolower(subpath);
					string* canonicalp = subpathl in filenameMappings;
					if (canonicalp && *canonicalp != subpath)
					{
						dirSegments[l] = dirSegments[l] ~ "_"; // not ~=
						goto again;
					}
					filenameMappings[subpathl] = subpath;
				}
				filename = join(dirSegments, "/");
			}

			return filename ~ ".asasm";
		}
	}

	ContextSet!(uint, true) privateNamespaces;
	ContextSet!(void*, false) objects, scripts;

	this(ASProgram as)
	{
		super(as);
	}

	bool[void*] orphans;
	void addOrphan(T)(T obj) { orphans[cast(void*)obj] = true; }
	bool isOrphan(T)(T obj) { return (cast(void*)obj in orphans) ? true : false; }

	override void run()
	{
		foreach (i, vclass; as.orphanClasses)
			addOrphan(vclass);
		foreach (i, method; as.orphanMethods)
			addOrphan(method);

		super.run();
		foreach (i, v; as.scripts)
		{
			ContextItem[][] classContexts;
			foreach (trait; v.traits)
			{
				auto c = ContextItem.expand(this, [ContextItem(trait.name)], true);
				if (c)
					classContexts ~= c;
			}
			context = reduce!contextRoot(new ContextItem[0], classContexts);
			if (context.length==0)
				pushContext("script_" ~ to!string(i));
			scripts.add(v, context);
			pushContext("sinit", true);
			addMethod(v.sinit);
			context = null;
		}
		foreach (i, vclass; as.orphanClasses)
			if (!objects.isAdded(vclass))
			{
				pushContext("orphan_class_" ~ to!string(i));
				addClass(vclass);
				popContext();
			}
		foreach (i, method; as.orphanMethods)
			if (!objects.isAdded(method))
			{
				pushContext("orphan_method_" ~ to!string(i));
				addMethod(method);
				popContext();
			}

		privateNamespaces.coagulate(this);
		objects.coagulate(this);
		scripts.coagulate(this);
	}

	override void visitTrait(ref ASProgram.Trait trait)
	{
		auto m = trait.name;

		if (m.kind != ASType.QName)
			throw new Exception("Trait name is not a QName");

		pushContext(m);
		visitMultiname(m);
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
				pushContext("getter");
				addMethod(trait.vMethod.vmethod);
				popContext();
				break;
			case TraitKind.Setter:
				pushContext("setter");
				addMethod(trait.vMethod.vmethod);
				popContext();
				break;
			default:
				break;
		}
		super.visitTrait(trait);
		popContext();
	}

	static ContextItem[] contextRoot(ContextItem[] c1, ContextItem[] c2)
	{
		static bool uninteresting(ContextItem[] c)
		{
			return
				(c.length==0) ||
				(c.length==1 && c[0].type==ContextItem.Type.String && c[0].str.startsWith("script_") && c[0].str.endsWith("_sinit")) ||
				(c.length==1 && c[0].type==ContextItem.Type.String && c[0].str.startsWith("orphan_method_")) ||
				false;
		}

		if (uninteresting(c1)) return c2;
		if (uninteresting(c2)) return c1;

		static bool nsSimilar(ASProgram.Namespace ns1, ASProgram.Namespace ns2)
		{
			if (ns1.kind==ASType.PrivateNamespace || ns2.kind==ASType.PrivateNamespace)
				return ns1.kind==ns2.kind && ns1.privateIndex==ns2.privateIndex;
			// ignore ns kind in other cases
			return ns1.name == ns2.name;
		}

		static bool similar(ref ContextItem i1, ref ContextItem i2)
		{
			if (i1.type != i2.type) return false;
			if (i1.type == ContextItem.Type.String)
				return i1.str == i2.str;
			if (i1.multiname.vQName.name != i2.multiname.vQName.name) return false;
			return nsSimilar(i1.multiname.vQName.ns, i2.multiname.vQName.ns);
		}

		int i=0;
		while (i<c1.length && i<c2.length && similar(c1[i], c2[i])) i++;
		auto c = c1[0..i];
		if (i<c1.length && i<c2.length && c1[i].type==ContextItem.Type.Multiname && c2[i].type==ContextItem.Type.Multiname && nsSimilar(c1[i].multiname.vQName.ns, c2[i].multiname.vQName.ns) && c1[i].multiname.vQName.ns.name.length)
		{
			auto m = new ASProgram.Multiname;
			m.kind = ASType.QName;
			m.vQName.ns = c1[i].multiname.vQName.ns;
			c ~= ContextItem(m);
		}
		return c;
	}

	void visitNamespace(ASProgram.Namespace ns)
	{
		if (ns.kind == ASType.PrivateNamespace)
		{
			assert(context.length > 0, "No context");
			//assert(ns.name is null, "Named private namespace");

			int myPos = context.length;
			foreach (i, ref item; context)
				if (item.type == ContextItem.Type.Multiname && item.multiname.vQName.ns == ns)
				{
					myPos = i;
					break;
				}
			if (myPos == 0)
				return;
			auto myContext = context[0..myPos].dup;

			privateNamespaces.add(ns.privateIndex, myContext);
		}
	}

	void visitNamespaceSet(ASProgram.Namespace[] nsSet)
	{
		foreach (ns; nsSet)
			visitNamespace(ns);
	}

	void visitMultiname(ASProgram.Multiname m)
	{
		with (m)
			switch (kind)
			{
				case ASType.QName:
				case ASType.QNameA:
					visitNamespace(vQName.ns);
					break;
				case ASType.Multiname:
				case ASType.MultinameA:
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
					break;
			}
	}

	void visitMethodBody(ASProgram.MethodBody b)
	{
		foreach (ref instruction; b.instructions)
			foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
				switch (type)
				{
					case OpcodeArgumentType.Namespace:
						visitNamespace(instruction.arguments[i].namespacev);
						break;
					case OpcodeArgumentType.Multiname:
						visitMultiname(instruction.arguments[i].multinamev);
						break;
					case OpcodeArgumentType.Class:
						pushContext("inline_class");
						if (isOrphan(instruction.arguments[i].classv))
							addClass(instruction.arguments[i].classv);
						popContext();
						break;
					case OpcodeArgumentType.Method:
						pushContext("inline_method");
						if (isOrphan(instruction.arguments[i].methodv))
							addMethod(instruction.arguments[i].methodv);
						popContext();
						break;
					default:
						break;
				}
	}

	string contextToString(ContextItem[] context, bool filename)
	{
		context = ContextItem.expand(this, context, false);

		foreach_reverse (i, c; context)
			if (i>0 && c==context[i-1])
				context = context[0..i] ~ context[i+1..$];

		ContextItem.Segment[] segments;
		foreach (ci; context)
			segments ~= ci.toSegments(filename);

		string escape(string s)
		{
			if (!filename)
				return s;

			string result;
			foreach (c; s)
				if (c == '.')
					result ~= '/';
				else
				if (c == ':' || c == '\\' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|' || c < 0x20 || c >= 0x7F)
					result ~= format("%%%02X", c);
				else
					result ~= c;
			return result;
		}

		string[] strings = new string[segments.length];
		foreach (i, ref s; segments)
			strings[i] = (i>0 ? cast(string)[s.delim] : null) ~ escape(s.str);

		return join(strings);
	}

	void addObject(T)(T obj) { objects.add(obj, context); }

	void addClass(ASProgram.Class vclass)
	{
		addObject(vclass);
		pushContext("cinit");
		addMethod(vclass.cinit);
		popContext();
		pushContext("iinit");
		addMethod(vclass.instance.iinit);
		popContext();
	}

	void addMethod(ASProgram.Method method)
	{
		addObject(method);
		if (method.vbody)
			visitMethodBody(method.vbody);
	}
}

final class Disassembler
{
	ASProgram as;
	string name, dir;
	RefBuilder refs;

	void newInclude(StringBuilder mainsb, string filename, void delegate(StringBuilder) callback)
	{
		if (mainsb.filename.split("/").length != 2)
			throw new Exception("TODO");
		StringBuilder sb = new StringBuilder(dir ~ "/" ~ filename);
		callback(sb);
		sb.save();

		mainsb ~= "#include ";
		dumpString(mainsb, filename);
		mainsb.newLine();
	}

	this(ASProgram as, string dir, string name)
	{
		this.as = as;
		this.name = name;
		this.dir = dir;
	}

	void disassemble()
	{
		refs = new RefBuilder(as);
		refs.run();

		StringBuilder sb = new StringBuilder(dir ~ "/" ~ name ~ ".main.asasm");

		sb ~= "#include ";
		dumpString(sb, name ~ ".privatens.asasm");
		sb.newLine();

		sb ~= "program";
		sb.indent++; sb.newLine();

		sb ~= "minorversion ";
		sb ~= to!string(as.minorVersion);
		sb.newLine();
		sb ~= "majorversion ";
		sb ~= to!string(as.majorVersion);
		sb.newLine();
		sb.newLine();

		foreach (i, script; as.scripts)
		{
			newInclude(sb, refs.scripts.getFilename(script), (StringBuilder sb) {
				dumpScript(sb, script, i);
			});
		}
		sb.newLine();

		if (as.orphanClasses.length)
		{
			sb ~= "; ============================= Orphan classes ==============================";
			sb.newLine();
			sb.newLine();

			foreach (i, vclass; as.orphanClasses)
				newInclude(sb, refs.objects.getFilename(vclass), (StringBuilder sb) {
					dumpClass(sb, vclass);
				});

			sb.newLine();
		}

		if (as.orphanMethods.length)
		{
			sb ~= "; ============================= Orphan methods ==============================";
			sb.newLine();
			sb.newLine();

			foreach (i, method; as.orphanMethods)
				newInclude(sb, refs.objects.getFilename(method), (StringBuilder sb) {
					dumpMethod(sb, method, "method");
				});

			sb.newLine();
		}

		sb.indent--;
		sb ~= "end ; program"; sb.newLine();

		sb.save();

		// now dump the private namespace indices
		sb = new StringBuilder(dir ~ "/" ~ name ~ ".privatens.asasm");
		uint[] indices = refs.privateNamespaces.names.keys;
		bool alphaSortDelegate(uint a, uint b) { return refs.privateNamespaces.names[a] < refs.privateNamespaces.names[b]; }
		sort!alphaSortDelegate(indices);
		foreach (index; indices)
		{
			void dumpContext(RefBuilder.ContextItem[] context)
			{
				sb ~= "; ";
				foreach (i, c; context)
				{
					if (c.type == RefBuilder.ContextItem.Type.Multiname)
						dumpMultiname(sb, c.multiname);
					else
						sb ~= c.str;
					if (i < context.length-1)
						sb ~= " -> ";
				}
				sb.newLine();
			}
			auto context = refs.privateNamespaces.contexts[index];
			dumpContext(context);
			/*auto contextEx = refs.ContextItem.expand(refs, context);
			if (context != contextEx)
				dumpContext(contextEx);*/

			sb ~= format("#privatens %4d ", index);
			dumpString(sb, refs.privateNamespaces.names[index]);
			sb.newLine();
		}
		sb.save();
	}

	void dumpInt(StringBuilder sb, long v)
	{
		if (v == ABCFile.NULL_INT)
			sb ~= "null";
		else
			sb ~= to!string(v);
	}

	void dumpUInt(StringBuilder sb, ulong v)
	{
		if (v == ABCFile.NULL_UINT)
			sb ~= "null";
		else
			sb ~= to!string(v);
	}

	void dumpDouble(StringBuilder sb, double v)
	{
		if (v == ABCFile.NULL_DOUBLE)
			sb ~= "null";
		else
		{
			string s = format("%.18g", v);

			static double forceDouble(double d) { static double n; n = d; return n; }
			if (s != "nan" && s!="inf" && s!="-inf")
				while (s.length>2 && s[$-1]!='.' && forceDouble(to!double(s[0..$-1]))==v)
					s = s[0..$-1];
			sb ~= s;
		}
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
				dumpString(sb, refs.privateNamespaces.getName(privateIndex));
			}
			sb ~= ')';
		}
	}

	void dumpNamespaceSet(StringBuilder sb, ASProgram.Namespace[] set)
	{
		if (set is null)
			sb ~= "null";
		else
		{
			sb ~= '[';
			foreach (i, ns; set)
			{
				dumpNamespace(sb, ns);
				if (i < set.length-1)
					sb ~= ", ";
			}
			sb ~= ']';
		}
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
			sb ~= TraitKindNames[trait.kind];
			sb ~= ' ';
			dumpMultiname(sb, trait.name);
			if (trait.attr)
				dumpFlags!(true)(sb, trait.attr, TraitAttributeNames);
			bool inLine = false;
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
					inLine = true;
					break;
				case TraitKind.Class:
					if (trait.vClass.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vClass.slotId);
					}
					sb.indent++; sb.newLine();
					dumpClass(sb, trait.vClass.vclass);
					break;
				case TraitKind.Function:
					if (trait.vFunction.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vFunction.slotId);
					}
					sb.indent++; sb.newLine();
					dumpMethod(sb, trait.vFunction.vfunction, "method");
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
					dumpMethod(sb, trait.vMethod.vmethod, "method");
					break;
				default:
					throw new Exception("Unknown trait kind");
			}

			foreach (metadata; trait.metadata)
			{
				if (inLine)
				{
					sb.indent++; sb.newLine();
					inLine = false;
				}
				dumpMetadata(sb, metadata);
			}

			if (inLine)
				{ sb ~= " end"; sb.newLine(); }
			else
				{ sb.indent--; sb ~= "end ; trait"; sb.newLine(); }
		}
	}

	void dumpMetadata(StringBuilder sb, ASProgram.Metadata metadata)
	{
		sb ~= "metadata ";
		dumpString(sb, metadata.name);
		sb.indent++; sb.newLine();
		foreach (ref item; metadata.items)
		{
			sb ~= "item ";
			dumpString(sb, item.key);
			sb ~= " ";
			dumpString(sb, item.value);
			sb.newLine();
		}
		sb.indent--; sb ~= "end ; metadata"; sb.newLine();
	}

	void dumpFlags(bool oneLine = false)(StringBuilder sb, ubyte flags, const string[] names)
	{
		for (int i=0; flags; i++, flags>>=1)
			if (flags & 1)
			{
				static if (oneLine)
					sb ~= " flag ";
				else
					sb ~= "flag ";
				sb ~= names[i];
				static if (!oneLine)
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

	void dumpMethod(StringBuilder sb, ASProgram.Method method, string label)
	{
		sb ~= label;
		sb.indent++; sb.newLine();
		if (method.name !is null)
		{
			sb ~= "name ";
			dumpString(sb, method.name);
			sb.newLine();
		}
		auto refName = refs.objects.getName(method);
		if (refName)
		{
			sb ~= "refid ";
			dumpString(sb, refName);
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

	void dumpClass(StringBuilder sb, ASProgram.Class vclass)
	{
		sb ~= "class"; sb.indent++; sb.newLine();

		auto refName = refs.objects.getName(vclass);
		if (refName)
		{
			sb ~= "refid ";
			dumpString(sb, refName);
			sb.newLine();
		}
		sb ~= "instance ";
		dumpInstance(sb, vclass.instance);
		dumpMethod(sb, vclass.cinit, "cinit");
		dumpTraits(sb, vclass.traits);

		sb.indent--; sb ~= "end ; class"; sb.newLine();
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
		dumpMethod(sb, instance.iinit, "iinit");
		dumpTraits(sb, instance.traits);
		sb.indent--; sb ~= "end ; instance"; sb.newLine();
	}

	void dumpScript(StringBuilder sb, ASProgram.Script script, uint index)
	{
		sb ~= "script ; ";
		sb ~= to!string(index);
		sb.indent++; sb.newLine();
		dumpMethod(sb, script.sinit, "sinit");
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

	void dumpLabel(StringBuilder sb, ref ABCFile.Label label)
	{
		sb ~= 'L';
		sb ~= to!string(label.index);
		if (label.offset != 0)
		{
			if (label.offset > 0)
				sb ~= '+';
			sb ~= to!string(label.offset);
		}
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

		bool[] labels = new bool[mbody.instructions.length+1];
		// reserve exception labels
		foreach (ref e; mbody.exceptions)
			labels[e.from.index] = labels[e.to.index] = labels[e.target.index] = true;

		sb.indent++;
		if (mbody.error)
		{
			sb ~= "; Error while disassembling method: " ~ mbody.error;
			sb.newLine();
		}
		else
			dumpInstructions(sb, mbody.instructions, labels);
		sb.indent--;

		sb ~= "end ; code";
		sb.newLine();
		foreach (ref e; mbody.exceptions)
		{
			sb ~= "try from ";
			dumpLabel(sb, e.from);
			sb ~= " to ";
			dumpLabel(sb, e.to);
			sb ~= " target ";
			dumpLabel(sb, e.target);
			sb ~= " type ";
			dumpMultiname(sb, e.excType);
			sb ~= " name ";
			dumpMultiname(sb, e.varName);
			sb ~= " end";
			sb.newLine();
		}
		dumpTraits(sb, mbody.traits);
		sb.indent--; sb ~= "end ; body"; sb.newLine();
	}

	void dumpInstructions(StringBuilder sb, ASProgram.Instruction[] instructions, bool[] labels)
	{
		foreach (ref instruction; instructions)
			foreach (i, type; opcodeInfo[instruction.opcode].argumentTypes)
				switch (type)
				{
					case OpcodeArgumentType.JumpTarget:
					case OpcodeArgumentType.SwitchDefaultTarget:
						labels[instruction.arguments[i].jumpTarget.index] = true;
						break;
					case OpcodeArgumentType.SwitchTargets:
						foreach (ref label; instruction.arguments[i].switchTargets)
							labels[label.index] = true;
						break;
					default:
						break;
				}

		void checkLabel(uint ii)
		{
			if (labels[ii])
			{
				sb.noIndent();
				sb ~= 'L';
				sb ~= to!string(ii);
				sb ~= ':';
				sb.newLine();
			}
		}

		bool extraNewLine = false;
		foreach (ii, ref instruction; instructions)
		{
			if (extraNewLine)
				sb.newLine();
			extraNewLine = newLineAfter[instruction.opcode];
			checkLabel(ii);

			sb ~= opcodeInfo[instruction.opcode].name;
			auto argTypes = opcodeInfo[instruction.opcode].argumentTypes;
			if (argTypes.length)
			{
				for (int i=opcodeInfo[instruction.opcode].name.length; i<20; i++)
					sb ~= ' ';
				foreach (i, type; argTypes)
				{
					final switch (type)
					{
						case OpcodeArgumentType.Unknown:
							throw new Exception("Don't know how to disassemble OP_" ~ opcodeInfo[instruction.opcode].name);

						case OpcodeArgumentType.UByteLiteral:
							sb ~= to!string(instruction.arguments[i].ubytev);
							break;
						case OpcodeArgumentType.IntLiteral:
							sb ~= to!string(instruction.arguments[i].intv);
							break;
						case OpcodeArgumentType.UIntLiteral:
							sb ~= to!string(instruction.arguments[i].uintv);
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
							dumpString(sb, refs.objects.getName(instruction.arguments[i].classv));
							break;
						case OpcodeArgumentType.Method:
							dumpString(sb, refs.objects.getName(instruction.arguments[i].methodv));
							break;

						case OpcodeArgumentType.JumpTarget:
						case OpcodeArgumentType.SwitchDefaultTarget:
							dumpLabel(sb, instruction.arguments[i].jumpTarget);
							break;

						case OpcodeArgumentType.SwitchTargets:
							sb ~= '[';
							auto targets = instruction.arguments[i].switchTargets;
							foreach (ti, t; targets)
							{
								dumpLabel(sb, t);
								if (ti < targets.length-1)
									sb ~= ", ";
							}
							sb ~= ']';
							break;
					}
					if (i < argTypes.length-1)
						sb ~= ", ";
				}
			}
			sb.newLine();
		}
		checkLabel(instructions.length);
	}
}

bool[256] newLineAfter;

static this()
{
	foreach (o; [
		Opcode.OP_callpropvoid,
		Opcode.OP_constructsuper,
		Opcode.OP_initproperty,
		Opcode.OP_ifeq,
		Opcode.OP_iffalse,
		Opcode.OP_ifge,
		Opcode.OP_ifgt,
		Opcode.OP_ifle,
		Opcode.OP_iflt,
		Opcode.OP_ifne,
		Opcode.OP_ifnge,
		Opcode.OP_ifngt,
		Opcode.OP_ifnle,
		Opcode.OP_ifnlt,
		Opcode.OP_ifstricteq,
		Opcode.OP_ifstrictne,
		Opcode.OP_iftrue,
		Opcode.OP_jump,
		Opcode.OP_lookupswitch,
		Opcode.OP_pushscope,
		Opcode.OP_returnvalue,
		Opcode.OP_returnvoid,
		Opcode.OP_setglobalslot,
		Opcode.OP_setlocal,
		Opcode.OP_setlocal0,
		Opcode.OP_setlocal1,
		Opcode.OP_setlocal2,
		Opcode.OP_setlocal3,
		Opcode.OP_setproperty,
		Opcode.OP_setpropertylate,
		Opcode.OP_setslot,
		Opcode.OP_setsuper
	])
		newLineAfter[o] = true;
}
