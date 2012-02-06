/*
 *  Copyright 2012 Vladimir Panteleev <vladimir@thecybershadow.net>
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

module lzma;

version(HAVE_LZMA) {} else static assert(0, "LZMA is not available (HAVE_LZMA version is not defined)");

import deimos.lzma;
import std.conv;
import std.exception;

version (Windows)
	{ pragma(lib, "liblzma"); }
else
	{ pragma(lib, "lzma"); }

align(1)
struct LZMAHeader
{
	ubyte compressionParameters;
	uint dictionarySize;
	long decompressedSize = -1;
}
static assert(LZMAHeader.sizeof == 13);

ubyte[] lzmaDecompress(LZMAHeader header, in ubyte[] compressedData)
{
    enforce(header.decompressedSize > 0, "Decompression with unknown size is unsupported");

    lzma_stream strm;
	lzmaEnforce(lzma_alone_decoder(&strm, ulong.max), "lzma_alone_decoder");
	scope(exit) lzma_end(&strm);

	auto outBuf = new ubyte[to!size_t(header.decompressedSize)];
	strm.next_out  = outBuf.ptr;
	strm.avail_out = outBuf.length;

	void decompress(in ubyte[] chunk)
	{
		strm.next_in  = chunk.ptr;
		strm.avail_in = chunk.length;
		lzmaEnforce(lzma_code(&strm, lzma_action.LZMA_RUN), "lzma_code");
		enforce(strm.avail_in == 0, "Not all data was read");
	}

	header.decompressedSize = -1; // Required as Flash uses End-of-Stream marker
	decompress(cast(ubyte[])(&header)[0..1]);
	decompress(compressedData);

	lzmaEnforce(lzma_code(&strm, lzma_action.LZMA_FINISH), "lzma_code");

	enforce(strm.avail_out == 0, "Decompressed size mismatch");

	return outBuf;
}

ubyte[] lzmaCompress(in ubyte[] decompressedData, LZMAHeader* header)
{
    lzma_options_lzma opts;
    enforce(lzma_lzma_preset(&opts, 9 | LZMA_PRESET_EXTREME) == false, "lzma_lzma_preset error");

    lzma_stream strm;
	lzmaEnforce(lzma_alone_encoder(&strm, &opts), "lzma_alone_encoder");
	scope(exit) lzma_end(&strm);

	auto outBuf = new ubyte[decompressedData.length];
	strm.next_out  = outBuf.ptr;
	strm.avail_out = outBuf.length;
	strm.next_in   = decompressedData.ptr;
	strm.avail_in  = decompressedData.length;
	lzmaEnforce(lzma_code(&strm, lzma_action.LZMA_RUN), "lzma_code");
	scope(failure) { import std.stdio; writeln("avail_in=", strm.avail_in); }
	enforce(strm.avail_in == 0, "Not all data was read");

	lzmaEnforce(lzma_code(&strm, lzma_action.LZMA_FINISH), "lzma_code");

	*header = *cast(LZMAHeader*)outBuf.ptr;
	return outBuf[LZMAHeader.sizeof..to!size_t(strm.total_out)];
}

private void lzmaEnforce(lzma_ret v, string f)
{
    if (v != lzma_ret.LZMA_OK && v != lzma_ret.LZMA_STREAM_END)
    	throw new Exception(text(f, " error: ", v));
}
