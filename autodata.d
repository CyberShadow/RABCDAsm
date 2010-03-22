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

module autodata;

import murmurhash2a;
import std2.traits;

string addAutoField(string name, bool reverseSort = false)
{
	//return `mixin(handler.process!(typeof(` ~ name ~ `), "` ~ name ~ `")());`; // doesn't work due to DMD bug 3959
	return `{ static const _AutoDataStr = handler.process!(typeof(this.` ~ name ~ `), "` ~ name ~ `", ` ~ (reverseSort ? "true" : "false") ~`)(); mixin(_AutoDataStr); }`;
}

template AutoCompare()
{
	hash_t toHash()
	{
		HashDataHandler handler;
		handler.hasher.Begin();
		processData!(void, "", "")(handler);
		return handler.hasher.End();
	}

	static if (is(typeof(this)==class))
		alias Object _AutoDataOtherType;
	else
		alias typeof(this) _AutoDataOtherType;

	int opEquals(_AutoDataOtherType other)
	{
		EqualsDataHandler!(typeof(this)) handler;
		static if (is(typeof(this)==class))
		{
			handler.other = cast(typeof(this)) other;
			if (handler.other is null)
				return false;
		}
		else
			handler.other = other;
		return processData!(bool, "auto _AutoDataOther = handler.other;", "return true;")(handler);
	}

	int opCmp(_AutoDataOtherType other)
	{
		CmpDataHandler!(typeof(this)) handler;
		static if (is(typeof(this)==class))
		{
			handler.other = cast(typeof(this)) other;
			if (handler.other is null)
				return -1;
		}
		else
			handler.other = other;
		return processData!(int, "auto _AutoDataOther = handler.other;", "return 0;")(handler);
	}
}

template AutoToString()
{
	string toString()
	{
		ToStringDataHandler handler;
		return processData!(string, "string _AutoDataResult;", "return _AutoDataResult;")(handler);
	}
}

template ProcessAllData()
{
	R processData(R, string prolog, string epilog, H)(ref H handler)
	{
		mixin(prolog);
		foreach (i, T; this.tupleof)
		{
			//mixin(addAutoField(T.stringof)); // doesn't work
			static if (this.tupleof[i].stringof == typeof(this.tupleof[i]).stringof)
				static assert(0, "DMD bug 2881 detected - can't use enums with ProcessAllData");
			else
			static if (is (typeof(this) == class))
				mixin(addAutoField(this.tupleof[i].stringof[5..$])); // remove "this."
			else
				mixin(addAutoField(this.tupleof[i].stringof[8..$])); // remove "(*this)."
		}
		mixin(epilog);
	}
}

/// For data handlers that only need to look at the raw data (currently only HashDataHandler)
template RawDataHandlerWrapper()
{
	static string process(T, string name, bool reverseSort)()
	{
		return processRecursive!(T, "this." ~ name, "");
	}

	static string processRecursive(T, string name, string loopDepth)()
	{
		static if (!hasAliasing!(T))
			return processRaw("&" ~ name, name ~ ".sizeof");
		else
		static if (is(T U : U[]))
		{
			string s = "{ bool _AutoDataNullTest = " ~ name ~ " is null; " ~ processRaw("&_AutoDataNullTest", "bool.sizeof") ~ "}";
			static if (!hasAliasing!(U))
				s ~= processRaw(name ~ ".ptr", name ~ ".length");
			else
				s ~= "foreach (ref _AutoDataArrayItem" ~ loopDepth ~ "; " ~ name ~ ") {" ~ processRecursive!(U, "_AutoDataArrayItem" ~ loopDepth, loopDepth~"Item")() ~ "}";
			return s;
		}
		else
		static if (is(typeof((new T).toHash())))
			//static assert(0, "aoeu: " ~ T.stringof);
			return name ~ ".processData!(void, ``, ``)(handler);";
		else
			static assert(0, "Don't know how to process type: " ~ T.stringof);
	}
}

struct HashDataHandler
{
	mixin RawDataHandlerWrapper;

	MurmurHash2A hasher;

	static string processRaw(string ptr, string len)
	{
		return "handler.hasher.Add(" ~ ptr ~ ", " ~ len ~ ");";
	}
}

struct EqualsDataHandler(O)
{
	O other;

	static string process(T, string name, bool reverseSort)()
	{
		string s;
		static if (is(T U : U[]))
			s ~= " if ((this." ~ name ~ " is null) != (_AutoDataOther." ~ name ~ " is null)) return false;";
		s ~= "if (this." ~ name ~ " != _AutoDataOther." ~ name ~ ") return false;";
		return s;
	}
}

struct CmpDataHandler(O)
{
	O other;

	static string process(T, string name, bool reverseSort)()
	{
		string reverseStr = reverseSort ? "-" : "";
		string s;
		static if (is(T U : U[]))
			s ~= "{ int _AutoDataCmp = cast(int)(this." ~ name ~ " !is null) - cast(int)(_AutoDataOther." ~ name ~ " !is null); if (_AutoDataCmp != 0) return " ~ reverseStr ~ "_AutoDataCmp; }";

		static if (is(T == string) && is(std.string.cmp))
			s ~= "{ int _AutoDataCmp = std.string.cmp(this." ~ name ~ ", _AutoDataOther." ~ name ~ "); if (_AutoDataCmp != 0) return " ~ reverseStr ~ "_AutoDataCmp; }";
		else
		static if (is(T == int))
			s ~= "{ int _AutoDataCmp = this." ~ name ~ " - _AutoDataOther." ~ name ~ "; if (_AutoDataCmp != 0) return " ~ reverseStr ~ "_AutoDataCmp; }"; // TODO: use long?
		else
		static if (is(typeof(T.opCmp)))
			s ~= "{ int _AutoDataCmp = this." ~ name ~ ".opCmp(_AutoDataOther." ~ name ~ "); if (_AutoDataCmp != 0) return " ~ reverseStr ~ "_AutoDataCmp; }";
		else
			s ~= "if (this." ~ name ~ " < _AutoDataOther." ~ name ~ ") return " ~ reverseStr ~ "(-1);" ~ 
			     "if (this." ~ name ~ " > _AutoDataOther." ~ name ~ ") return " ~ reverseStr ~ "( 1);";
		return s;
	}
}

struct ToStringDataHandler
{
	static string process(T, string name, bool reverseSort)()
	{
		return "_AutoDataResult ~= format(`%s = %s `, `" ~ name ~ "`, this." ~ name ~ ");";
	}
}
