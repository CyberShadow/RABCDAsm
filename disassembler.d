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

module disassembler;

import std.file;
import std.string;
import std.array;
import std.conv;
import std.exception;
import std.algorithm;
import std.path;
import std.md5;
import abcfile;
import asprogram;
import autodata;
import common;

alias std.array.join join;

final class StringBuilder
{
	char[] buf;
	size_t pos;
	string filename;

	this(string filename)
	{
		if (exists(longPath(filename)))
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
			if (subdir.length && !exists(longPath(subdir)))
				mkdir(longPath(subdir));
		}
		write(longPath(filename), buf[0..pos]);
	}

	int indent;
	bool indented;
	string linePrefix;

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
			if (linePrefix)
				this ~= linePrefix;
		}
	}
}

final class RefBuilder : ASTraitsVisitor
{
	bool[uint][string][ASType.Max] homonyms;
	debug bool homonymsBuilt;

	bool hasHomonyms(ASProgram.Namespace ns)
	{
		debug assert(homonymsBuilt);
		auto pnsHomonyms = ns.name in homonyms[ns.kind];
		auto nsHomonyms = pnsHomonyms ? *pnsHomonyms : null;
		return nsHomonyms.length > 1;
	}

	void addHomonym(ASProgram.Namespace ns)
	{
		debug assert(!homonymsBuilt);
		homonyms[ns.kind][ns.name][ns.id] = true;
	}

	/// Represents a link in a "context chain", which represents the context in which an object is encountered.
	/// The common root of contexts is used to build ref strings, namespace labels, file paths etc.
	/// Expansion is recursive and delayed until decompilation (an object may be encountered inside a private namespace,
	/// all contexts of which are unknown until the whole program is scanned).
	struct ContextItem
	{
		enum Type
		{
			Multiname, /// An ASProgram.Multiname (may be a private namespace, etc.)
			String,    /// Fixed string
			Group,     /// Multiple ContextItem[]s (which are expanded and the common root is taken as the result)
		}
		Type type;

		union
		{
			ASProgram.Multiname multiname;
			struct
			{
				string str;
				bool filenameSuffix;
			}
			struct
			{
				ContextItem[] group;
				string groupFallback;
			}
		}

		struct Segment
		{
			char delim;
			string str;
		}

		ContextItem[] reduceGroup(RefBuilder refs)
		{
			assert(type==Type.Group);

			ContextItem[][] contexts;
			foreach (context; group)
				contexts ~= ContextItem.expand(refs, [context]);

			ContextItem[] context;
			if (contexts.length)
				context = reduce!contextRoot(contexts);
			if (!context.length)
				context = /*null*/[ContextItem(groupFallback)];
			return context;
		}

		Segment[] toSegments(RefBuilder refs, bool filename)
		out(result)
		{
			debug(CONTEXTS) std.stdio.writefln("Segmented:\n\t%s\nto\n\t%s\n", this, result);
		}
		body
		{
			final switch(type)
			{
				case Type.Multiname:
				{
					assert(multiname.kind == ASType.QName);
					auto ns = multiname.vQName.ns;
					auto nsName = ns.name;
				//	if (refs.hasHomonyms(ns))
				//		nsName ~= '#' ~ to!string(ns.id);
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
				}
				case Type.String:
					return [Segment(filenameSuffix ? '.' : '/', str)];
				case Type.Group:
				{
					Segment[] segments;
					foreach (context; reduceGroup(refs))
						segments ~= context.toSegments(refs, filename);
					return segments;
				}
			}
		}

		static ContextItem[] expand(RefBuilder refs, ContextItem[] context)
		{
			ContextItem[] newContext;
			foreach (ref c; context)
			{
				auto cEx = c.expand(refs);
				if (cEx)
					newContext ~= cEx;
			}
			return newContext;
		}

		bool expanding;

		/// Recursively expand contexts (lower to Type.String ContextItems)
		ContextItem[] expand(RefBuilder refs)
		in
		{
			debug(CONTEXTS) std.stdio.writefln("Expanding:\n\t%s\n", this);
		}
		out(result)
		{
			debug(CONTEXTS) std.stdio.writefln("Expanded:\n\t%s\nto\n\t%s\n", this, result);
		}
		body
		{
			if (expanding)
				final switch (type)
				{
					case Type.String:
						assert(0);
					case Type.Multiname:
						return (&this)[0..1];
					case Type.Group:
						return [ContextItem(groupFallback)];
				}

			assert(!expanding);
			expanding = true;
			scope(exit) expanding = false;

			final switch (type)
			{
				case Type.Multiname:
					auto ns = multiname.vQName.ns;
					if (ns.kind == ASType.PrivateNamespace)
					{
					//	auto pcontext = ns.id in refs.namespaces[ns.kind].contexts;
					//	if (pcontext is null)
					//		return (&this)[0..1];
					//	assert(pcontext);
						auto context = refs.namespaces[ns.kind].getContext(refs, ns.id);
						debug(CONTEXTS) std.stdio.writefln("Context of namespace %s is:\n\t%s\n", ns, context);
					//	auto expanded = expand(refs, context);
					//	if (expanded is null) return null;
						return /*expanded*/context ~ (multiname.vQName.name.length ? [ContextItem(multiname.vQName.name)] : null); // hack
					}
					break;
				case Type.String:
					break;
				case Type.Group:
					return reduceGroup(refs);
			}

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

		this(ContextItem[] group, string groupFallback)
		{
			this.type = Type.Group;
			this.group = group;
			this.groupFallback = groupFallback;
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
				case Type.Group:
					mixin(addAutoField("group"));
					mixin(addAutoField("groupFallback"));
					break;
			}
			mixin(epilog);
		}

		static bool similar(ref ContextItem i1, ref ContextItem i2)
		{
			if (i1.type != i2.type) return false;
			final switch (i1.type)
			{
				case ContextItem.Type.String:
					return i1.str == i2.str;
				case ContextItem.Type.Multiname:
					if (i1.multiname.vQName.name != i2.multiname.vQName.name) return false;
					return nsSimilar(i1.multiname.vQName.ns, i2.multiname.vQName.ns);
				case ContextItem.Type.Group:
					return i1.group == i2.group;
			}
		}

		// truncate=true  -> return partial ContextItem
		// truncate=false -> return null on partial match
		static ContextItem[] combine(bool truncate)(ref ContextItem c1, ref ContextItem c2)
		{
			if (similar(c1, c2))
				return [c1];

			if (c1.type != ContextItem.Type.Multiname || c2.type != ContextItem.Type.Multiname)
				return null;
			if (c1.multiname.kind != ASType.QName || c2.multiname.kind != ASType.QName)
				return null;

			auto name1 = c1.multiname.vQName.name;
			auto name2 = c2.multiname.vQName.name;
			auto ns1   = c1.multiname.vQName.ns;
			auto ns2   = c2.multiname.vQName.ns;

			if (nsSimilar(ns1, ns2) && ns1.name.length && truncate)
			{
				auto m = new ASProgram.Multiname;
				m.kind = ASType.QName;
				m.vQName.ns = ns1;
				return [ContextItem(m)];
			}

			if (name1 && !name2 && truncate)
			{
				swap(c1, c2);
				swap(ns1, ns2);
				swap(name1, name2);
			}

			if (!name1 && name2 && nsSimilar(ns1, ns2))
			{
				if (truncate)
				{
					auto m = new ASProgram.Multiname;
					m.kind = ASType.QName;
					m.vQName.ns = ns1;
					return [ContextItem(m)];
				}
				else
					return [c2];
			}

			if (ns1.name.length && ns2.name.length)
			{
				if (nsSimilar(ns1, ns2))
				{
					assert(name1 != name2); // handled by similar() check
					static if (truncate)
						assert(false); // handled above
					else
					{
						if (name2.length)
							return [c1, ContextItem(name2)];
						else
							return [c1];
					}
				}

				if (ns1.name.length > ns2.name.length && truncate)
				{
					swap(c1, c2);
					swap(ns1, ns2);
					swap(name1, name2);
				}

				auto fullName1 = ns1.name ~ (name1 ? ':' ~ name1 : "");
				auto fullName2 = ns2.name ~ (name2 ? ':' ~ name2 : "");
				if (fullName2.startsWith(fullName1 ~ ":"))
					return [truncate ? c1 : c2];
			}

			return null;
		}

		alias combine!true commonRoot;
		alias combine!false deduplicate;
	}

	ContextItem[] context; // potential optimization: use array-based stack

	void pushContext(T...)(T v) { context ~= ContextItem(v); }
	void popContext() { context = context[0..$-1]; }

	struct ContextSet(T, bool ALLOW_DUPLICATES)
	{
		ContextItem[][T] contexts;
		ContextItem[][][T] contextSets;
		debug bool contextsSealed;

		string[T] names, filenames;
		debug bool coagulated;

		bool add(U)(U obj, ContextItem[] context)
		{
			debug assert(!coagulated);
			debug assert(!contextsSealed);

			auto p = cast(T)obj;
			auto pset = p in contextSets;

			if (!pset)
			{
				contextSets[p] ~= context.dup;
				return true;
			}
			else
			{
				if ((*pset)[$-1] != context)
					*pset ~= context.dup;
				return false;
			}
		}

		bool addIfNew(U)(U obj, ContextItem[] context)
		{
			if (isAdded(obj))
				return false;
			else
				return add(obj, context);
		}

		void coagulate(RefBuilder refs)
		{
			debug assert(!coagulated);

			int[string] collisionCounter;
			T[string] first;

			foreach (obj, set; contextSets)
				if (obj !in contexts)
					getContext(refs, obj);

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

			debug coagulated = true;
		}

		bool isAdded(U)(U obj) { return (cast(T)obj in contextSets) ? true : false; }

		ContextItem[] getContext(U)(RefBuilder refs, U obj)
		{
		//	debug assert(coagulated);
			debug contextsSealed = true;

			auto p = cast(T)obj;
			auto pcontext = p in contexts;
			if (pcontext)
				return *pcontext;

			auto set = contextSets[p];

			static if (ALLOW_DUPLICATES)
			{
				auto context = ContextItem.expand(refs, set[0]);
				foreach (setContext; set[1..$])
					context = contextRoot(context, ContextItem.expand(refs, setContext));
				return contexts[p] = context;
			}
			else
			{
				if (set.length > 1)
					return contexts[p] = [ContextItem("multireferenced")];
				else
					return contexts[p] = ContextItem.expand(refs, set[0]);
			}
		}

		string getName(U)(U obj)
		{
			debug assert(coagulated);

			auto pname = cast(T)obj in names;
		//	return pname?*pname:"##" ~ format(obj);
			assert(pname, format("Unscanned object: ", obj));
			return *pname;
		}

		static string[string] filenameMappings;

		string getFilename(U)(U obj, string suffix)
		{
			debug assert(coagulated);

			auto pname = cast(T)obj in filenames;
			assert(pname, format("Unscanned object: ", obj));
			auto filename = *pname;

			string[] dirSegments = split(filename, "/");
			for (int l=0; l<dirSegments.length; l++)
			{
			again:
				string subpath = join(dirSegments[0..l+1], "/");
				string subpathl = toLower(subpath);
				string* canonicalp = subpathl in filenameMappings;
				if (canonicalp && *canonicalp != subpath)
				{
					dirSegments[l] = dirSegments[l] ~ "_"; // not ~=
					goto again;
				}
				filenameMappings[subpathl] = subpath;
			}
			filename = join(dirSegments, "/");

			return filename ~ "." ~ suffix ~ ".asasm";
		}
	}

	ContextSet!(uint, true)[ASType.Max] namespaces;
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
			ContextItem[] classContexts;

			foreach (trait; v.traits)
				if (trait.name.vQName.ns.kind != ASType.PrivateNamespace)
					classContexts ~= ContextItem(trait.name);

			if (!classContexts.length)
				foreach (trait; v.traits)
					classContexts ~= ContextItem(trait.name);

			context = [ContextItem(classContexts, "script_" ~ to!string(i))];
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

		scripts.coagulate(this);

		// add namespaces referenced only at script level
		foreach (v; as.scripts)
			foreach (trait; v.traits)
				if (trait.name.kind == ASType.QName)
					namespaces[trait.name.vQName.ns.kind].addIfNew(trait.name.vQName.ns.id, scripts.getContext(this, v));

		foreach (id, b; possibleOrphanPrivateNamespaces)
			if (!namespaces[ASType.PrivateNamespace].isAdded(id))
			{
				pushContext("orphan_namespace_" ~ to!string(id));
				namespaces[ASType.PrivateNamespace].add(id, context);
				popContext();
			}

		debug homonymsBuilt = true;
		foreach (ref namespace; namespaces)
			namespace.coagulate(this);
		objects.coagulate(this);
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
			// Do some validation while we're at it
			foreach (cc; c)
				assert(cc.type != ContextItem.Type.Group, "Groups should be expanded by now");

			return
				(c.length==1 && c[0].type==ContextItem.Type.String && c[0].str.startsWith("script_") && c[0].str.endsWith("_sinit")) ||
				(c.length==1 && c[0].type==ContextItem.Type.String && c[0].str.startsWith("orphan_method_")) ||
				false;
		}

		if (uninteresting(c1)) return c2;
		if (uninteresting(c2)) return c1;

		ContextItem[] c;
		while (c.length<c1.length && c.length<c2.length)
		{
			auto root = ContextItem.commonRoot(c1[c.length], c2[c.length]);
			assert(root.length <= 1);
			if (root.length)
				c ~= root;
			else
				break;
		}
		return c;
	}

	bool[uint] possibleOrphanPrivateNamespaces;

	void visitNamespace(ASProgram.Namespace ns)
	{
		if (ns is null) return;

		// Add to homonyms

		addHomonym(ns);

		// Add to namespaces (for context)

		assert(context.length > 0, "No context");

		auto myPos = context.length;
		foreach (i, ref item; context)
			if (item.type == ContextItem.Type.Multiname && item.multiname.vQName.ns == ns)
			{
				myPos = i;
				break;
			}
		if (ns.kind == ASType.PrivateNamespace && myPos == 0)
		{
			possibleOrphanPrivateNamespaces[ns.id] = true;
			return;
		}

		auto myContext = context[0..myPos].dup;
		namespaces[ns.kind].add(ns.id, myContext);
	}

	void visitNamespaceSet(ASProgram.Namespace[] nsSet)
	{
		foreach (ns; nsSet)
			visitNamespace(ns);
	}

	void visitMultiname(ASProgram.Multiname m)
	{
		if (m is null) return;
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
	in
	{
		debug(CONTEXTS) std.stdio.writefln("Stringizing:\n\t%s\n", context);
	}
	out(result)
	{
		debug(CONTEXTS) std.stdio.writefln("Stringized:\n\t%s\nto\n\t%s\n------------------\n", context, result);
	}
	body
	{
		context = ContextItem.expand(this, context);
		if (!context.length)
			return null;

		foreach_reverse (i; 0..context.length-1)
		{
			auto root = ContextItem.deduplicate(context[i], context[i+1]);
			if (root.length)
				context = context[0..i] ~ root ~ context[i+2..$];
		}

		ContextItem.Segment[] segments;
		foreach (ci; context)
			segments ~= ci.toSegments(this, filename);

		string escape(string s)
		{
			if (!filename)
				return s;

			string result;
			foreach (c; s)
				if (c == '.' || c == ':')
					result ~= '/';
				else
				if (c == '\\' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|' || c < 0x20 || c >= 0x7F || c == ' ' || c == '%')
					result ~= format("%%%02X", c);
				else
					result ~= c;

			auto pathSegments = result.split("/");
			if (!pathSegments.length)
				pathSegments = [""];
			foreach (ref pathSegment; pathSegments)
			{
				if (pathSegment == "")
					pathSegment = "%";

				static const reservedNames = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"];
				auto pathSegmentU = pathSegment.toUpper();
				foreach (reservedName; reservedNames)
					if (pathSegmentU.startsWith(reservedName) && (pathSegmentU.length == reservedName.length || pathSegmentU[reservedName.length]=='.'))
					{
						pathSegment = "%" ~ pathSegment;
						break;
					}

				if (pathSegment.length > 240)
					pathSegment = pathSegment[0..200] ~ '-' ~ getDigestString(pathSegment);
			}

			return arrayJoin(pathSegments, "/");
		}

		string[] strings = new string[segments.length];
		foreach (i, ref s; segments)
			strings[i] = (i>0 ? cast(string)[s.delim] : null) ~ escape(s.str);

		return arrayJoin(strings);
	}

	bool addObject(T)(T obj) { return objects.add(obj, context); }

	void addClass(ASProgram.Class vclass)
	{
		addObject(vclass);

		pushContext("cinit");
		addMethod(vclass.cinit);
		popContext();

		pushContext("iinit");
		addMethod(vclass.instance.iinit);
		popContext();

		pushContext("instance");
		visitMultiname(vclass.instance.name);
		visitMultiname(vclass.instance.superName);
		foreach (iface; vclass.instance.interfaces)
			visitMultiname(iface);
		popContext();
	}

	void addMethod(ASProgram.Method method)
	{
		if (addObject(method))
		{
			foreach (paramType; method.paramTypes)
				visitMultiname(paramType);
			visitMultiname(method.returnType);
			if (method.vbody)
				visitMethodBody(method.vbody);
		}
	}
}

final class Disassembler
{
	ASProgram as;
	string name, dir;
	RefBuilder refs;

	void newInclude(StringBuilder mainsb, string filename, void delegate(StringBuilder) callback, bool doInline = true)
	{
		if (doInline)
		{
			string base = dirName(mainsb.filename);
			string full = dir ~ "/" ~ filename;
			uint up = 0;
			while (!full.startsWith(base))
				base = dirName(base), up++;
			string rel  = replicate("../", up) ~ full[base.length+1..$];

			StringBuilder sb = new StringBuilder(full);
			callback(sb);
			sb.save();

			mainsb ~= "#include ";
			dumpString(mainsb, rel);
			mainsb.newLine();
		}
		else
			callback(mainsb);
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

		sb ~= "#version 3";
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

		foreach (uint i, script; as.scripts)
		{
			auto ii = i; // http://d.puremagic.com/issues/show_bug.cgi?id=8526
			newInclude(sb, refs.scripts.getFilename(script, "script"), (StringBuilder sb) {
				dumpScript(sb, script, ii);
			});
		}
		sb.newLine();

		if (as.orphanClasses.length)
		{
			sb ~= "; ============================= Orphan classes ==============================";
			sb.newLine();
			sb.newLine();

			foreach (i, vclass; as.orphanClasses)
				newInclude(sb, refs.objects.getFilename(vclass, "class"), (StringBuilder sb) {
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
				newInclude(sb, refs.objects.getFilename(method, "method"), (StringBuilder sb) {
					dumpMethod(sb, method, "method");
				});

			sb.newLine();
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
			if (s != "nan" && s != "inf" && s != "-inf")
			{
				foreach_reverse (i; 1..s.length)
					if (s[i]>='0' && s[i]<='8' && forceDouble(to!double(s[0..i] ~ cast(char)(s[i]+1)))==v)
						s = s[0..i] ~ cast(char)(s[i]+1);
				while (s.length>2 && s[$-1]!='.' && forceDouble(to!double(s[0..$-1]))==v)
					s = s[0..$-1];
			}
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
		{
			sb ~= ASTypeNames[namespace.kind];
			sb ~= '(';
			dumpString(sb, namespace.name);
			if (refs.hasHomonyms(namespace))
			{
				sb ~= ", ";
				auto label = refs.namespaces[namespace.kind].getName(namespace.id);
			//	label ~= format(" (%d)", namespace.id);
				dumpString(sb, label);
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

	void dumpTraits(StringBuilder sb, ASProgram.Trait[] traits, bool inScript = false)
	{
		foreach (/*ref*/ trait; traits)
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

					newInclude(sb, refs.objects.getFilename(trait.vClass.vclass, "class"), (StringBuilder sb) {
						dumpClass(sb, trait.vClass.vclass);
					});
					break;
				case TraitKind.Function:
					if (trait.vFunction.slotId)
					{
						sb ~= " slotid ";
						dumpUInt(sb, trait.vFunction.slotId);
					}
					sb.indent++; sb.newLine();
					newInclude(sb, refs.objects.getFilename(trait.vFunction.vfunction, "method"), (StringBuilder sb) {
						dumpMethod(sb, trait.vFunction.vfunction, "method");
					}, inScript);
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
					newInclude(sb, refs.objects.getFilename(trait.vMethod.vmethod, "method"), (StringBuilder sb) {
						dumpMethod(sb, trait.vMethod.vmethod, "method");
					}, inScript);
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
		assert(metadata.keys.length == metadata.values.length);
		foreach (i; 0..metadata.keys.length)
		{
			sb ~= "item ";
			dumpString(sb, metadata.keys[i]);
			sb ~= " ";
			dumpString(sb, metadata.values[i]);
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
	//	sb ~= format(" ; %d", method.id);
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
		dumpTraits(sb, script.traits, true);
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
		if (mbody.error)
		{
			sb ~= "; Error while disassembling method: " ~ mbody.error;
			sb.newLine();
			sb.linePrefix = "; ";
		}

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
			foreach (i, b; mbody.rawBytes)
			{
				sb ~= format("0x%02X", b);
				if (i%16==15 || i==mbody.rawBytes.length-1)
					sb.newLine();
				else
					sb ~= " ";
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
		sb.linePrefix = null;
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
		foreach (uint ii, ref instruction; instructions)
		{
			if (extraNewLine)
				sb.newLine();
			extraNewLine = newLineAfter[instruction.opcode];
			checkLabel(ii);

			sb ~= opcodeInfo[instruction.opcode].name;
			auto argTypes = opcodeInfo[instruction.opcode].argumentTypes;
			if (argTypes.length)
			{
				foreach (i; opcodeInfo[instruction.opcode].name.length..20)
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
							if (instruction.arguments[i].classv is null)
								sb ~= "null";
							else
								dumpString(sb, refs.objects.getName(instruction.arguments[i].classv));
							break;
						case OpcodeArgumentType.Method:
							if (instruction.arguments[i].methodv is null)
								sb ~= "null";
							else
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
		checkLabel(to!uint(instructions.length));
	}
}

private:

bool nsSimilar(ASProgram.Namespace ns1, ASProgram.Namespace ns2)
{
	if (ns1.kind==ASType.PrivateNamespace || ns2.kind==ASType.PrivateNamespace)
		return ns1.kind==ns2.kind && ns1.id==ns2.id;
	// ignore ns kind in other cases
	return ns1.name == ns2.name;
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
		Opcode.OP_setsuper,
		Opcode.OP_si8,
		Opcode.OP_si16,
		Opcode.OP_si32,
		Opcode.OP_sf32,
		Opcode.OP_sf64,
	])
		newLineAfter[o] = true;
}

/// Force a raw data join (workaround for issue 6064)
T[] arrayJoin(T)(T[][] arrays, T[] sep)
{
	return cast(T[])join(cast(ubyte[][])arrays, cast(ubyte[])sep);
}

/// ditto
T[] arrayJoin(T)(T[][] arrays)
{
	return cast(T[])join(cast(ubyte[][])arrays);
}
