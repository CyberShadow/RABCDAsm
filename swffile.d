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

module swffile;

import std.zlib;

/** 
 * Implements a shallow representation of a .swf file. 
 * Loading and saving a .swf file using this class should produce
 * output identical to the input (aside zlib compression differences).
 */

final class SWFFile
{
	Header header;
	Rect frameSize;
	ushort frameRate, frameCount;
	Tag[] tags;

	align(1) struct Header
	{
		char[3] signature;
		ubyte ver;
		uint fileLength;
		static assert(Header.sizeof == 8);
	}

	struct Rect
	{
		//int xMin, xMax, yMin, yMax;
		ubyte[] bytes;
	}

	struct Tag
	{
		ushort type;
		ubyte[] data;
		bool forceLongLength;
	}

	static SWFFile read(ubyte[] data)
	{
		return (new SWFReader(data)).swf;
	}

	ubyte[] write()
	{
		return SWFWriter.write(this);
	}
}

private final class SWFReader
{
	ubyte[] buf;
	size_t pos;
	SWFFile swf;

	this(ubyte[] data)
	{
		buf = data;
		swf = new SWFFile();

		readRaw((&swf.header)[0..1]);
		if ((swf.header.signature[0] != 'F' && swf.header.signature[0] != 'C') || swf.header.signature[1] != 'W' || swf.header.signature[2] != 'S')
			throw new Exception("Invalid file signature");
		if (swf.header.signature[0] == 'C')
		{
			buf = buf[0..8] ~ cast(ubyte[])uncompress(buf[8..$], swf.header.fileLength-8);
			assert(buf.length == swf.header.fileLength);
		}
		swf.frameSize = readRect();
		swf.frameRate = readU16();
		swf.frameCount = readU16();

		while (pos < buf.length)
			swf.tags ~= readTag();
	}

	void readRaw(void[] raw)
	{
		raw[] = buf[pos..pos+raw.length];
		pos += raw.length;
	}

	void[] readRaw(size_t len)
	{
		auto data = buf[pos..pos+len];
		pos += len;
		return data;
	}

	version(LittleEndian) {} else static assert(0, "Big endian platforms not supported");

	ushort readU16()
	{
		ushort r;
		readRaw((&r)[0..1]);
		return r;
	}

	uint readU32()
	{
		uint r;
		readRaw((&r)[0..1]);
		return r;
	}

	SWFFile.Rect readRect()
	{
		SWFFile.Rect r;
		ubyte b = buf[pos];
		uint nbits = b >> 3;
		uint nbytes = ((5 + 4*nbits) + 7) / 8;
		r.bytes = cast(ubyte[])readRaw(nbytes);
		return r;
	}

	SWFFile.Tag readTag()
	{
		SWFFile.Tag t;
		ushort u = readU16();
		t.type = cast(ushort)(u >> 6);
		uint length = u & 0x3F;
		if (length == 0x3F)
		{
			length = readU32();
			if (length < 0x3F)
				t.forceLongLength = true;
		}
		t.data = cast(ubyte[])readRaw(length);
		return t;
	}
}

enum TagType
{
	End						= 0,
	ShowFrame				= 1,
	DefineShape				= 2,
	FreeCharacter			= 3,
	PlaceObject				= 4,
	RemoveObject			= 5,
	DefineBits				= 6,
	DefineButton			= 7,
	JPEGTables				= 8,
	SetBackgroundColor		= 9,
	DefineFont				= 10,
	DefineText				= 11,
	DoAction				= 12,
	DefineFontInfo			= 13,
	DefineSound				= 14,
	StartSound				= 15,
	DefineButtonSound		= 17,
	SoundStreamHead			= 18,
	SoundStreamBlock		= 19,
	DefineBitsLossless		= 20,
	DefineBitsJPEG2			= 21,
	DefineShape2			= 22,
	DefineButtonCxform		= 23,
	Protect					= 24,
	PathsArePostScript		= 25,
	PlaceObject2			= 26,
	RemoveObject2			= 28,
	DefineShape3			= 32,
	DefineText2				= 33,
	DefineButton2			= 34,
	DefineBitsJPEG3			= 35,
	DefineBitsLossless2		= 36,
	DefineSprite			= 39,
	ProductInfo				= 41,
	FrameLabel				= 43,
	SoundStreamHead2		= 45,
	DefineMorphShape		= 46,
	DefineFont2				= 48,
	DefineEditText			= 37,
	ExportAssets			= 56,
	ImportAssets			= 57,
	EnableDebugger			= 58,
	DoInitAction			= 59,
	DefineVideoStream		= 60,
	VideoFrame				= 61,
	DefineFontInfo2			= 62,
	DebugID					= 63,
	EnableDebugger2			= 64,
    ScriptLimits			= 65,
    SetTabIndex				= 66,
	FileAttributes			= 69,
	PlaceObject3			= 70,
	ImportAssets2			= 71,
	DoABC					= 72,
    DefineFontAlignZones	= 73,
    CSMTextSettings     	= 74,
    DefineFont3				= 75,
	SymbolClass				= 76,
    Metadata                = 77,
    DefineScalingGrid       = 78,
    DoABC2                  = 82,
    DefineShape4            = 83,
	DefineMorphShape2		= 84,
    DefineSceneAndFrameLabelData = 86,
    DefineBinaryData        = 87,
	DefineFontName          = 88,
	DefineFont4             = 91
}

private final class SWFWriter
{
	static ubyte[] write(SWFFile swf)
	{
		ubyte[] buf;

		buf ~= swf.frameSize.bytes;
		buf ~= toArray(swf.frameRate);
		buf ~= toArray(swf.frameCount);
		
		foreach (ref tag; swf.tags)
		{
			ushort u = cast(ushort)(tag.type << 6);
			if (tag.data.length < 0x3F && !tag.forceLongLength)
			{
				u |= tag.data.length;
				buf ~= toArray(u);
			}
			else
			{
				u |= 0x3F;
				buf ~= toArray(u);
				uint l = tag.data.length;
				buf ~= toArray(l);
			}
			buf ~= tag.data;
		}

		swf.header.fileLength = 8 + buf.length;
		if (swf.header.signature[0] == 'C')
			buf = cast(ubyte[])compress(buf, 9);
		buf = toArray(swf.header) ~ buf;

		return buf;
	}

	static ubyte[] toArray(T)(ref T v)
	{
		return cast(ubyte[])(&v)[0..1];
	}
}
