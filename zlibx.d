/// This code is in the public domain.

module zlibx;

import std.string : format;
import std.zlib, etc.c.zlib, std.conv;
static import etc.c.zlib;
alias std.zlib.Z_SYNC_FLUSH Z_SYNC_FLUSH;
debug import std.stdio : stderr;

/// Avoid bug(?) in D zlib implementation with 7zip-generated zlib streams
ubyte[] exactUncompress(ubyte[] srcbuf, size_t destlen)
{
	etc.c.zlib.z_stream zs;

	auto destbuf = new ubyte[destlen];
	uint err;

	zs.next_in = srcbuf.ptr;
	zs.avail_in = to!uint(srcbuf.length);

	zs.next_out = destbuf.ptr;
	zs.avail_out = to!uint(destbuf.length);

	err = etc.c.zlib.inflateInit2(&zs, 15);
	if (err)
	{
		delete destbuf;
		throw new ZlibException(err);
	}

	while (true)
	{
		err = etc.c.zlib.inflate(&zs, Z_SYNC_FLUSH);
		if (err != Z_OK && err != Z_STREAM_END)
		{
		Lerr:
			delete destbuf;
			etc.c.zlib.inflateEnd(&zs);
			throw new ZlibException(err);
		}

		if (err == Z_STREAM_END)
			break;
		else
		if (zs.avail_out == 0)
		{
			debug stderr.writefln("Wrong uncompressed file length (read %d/%d bytes and wrote %d/%d bytes)",
				srcbuf .length - zs.avail_in , srcbuf .length,
				destlen        - zs.avail_out, destlen);
			auto out_pos = zs.next_out - destbuf.ptr;
			destbuf.length = 1024 + destbuf.length * 2;
			zs.next_out = destbuf.ptr + out_pos;
			zs.avail_out = to!uint(destbuf.length - out_pos);
			continue;
		}
		else
		if (zs.avail_in == 0)
		{
			debug stderr.writefln("Unterminated Zlib stream (read %d/%d bytes and wrote %d/%d bytes)",
				srcbuf .length - zs.avail_in , srcbuf .length,
				destlen        - zs.avail_out, destlen);
			break;
		}
		else
			throw new Exception(format("Unexpected zlib state (err=%d, avail_in == %d, avail_out = %d)",
					err, zs.avail_in , zs.avail_out));
	}

	if (zs.avail_in != 0 || zs.avail_out != 0)
		debug stderr.writefln("Zlib stream incongruity (read %d/%d bytes and wrote %d/%d bytes)",
				srcbuf .length - zs.avail_in , srcbuf .length,
				destlen        - zs.avail_out, destlen);

	err = etc.c.zlib.inflateEnd(&zs);
	if (err != Z_OK)
		goto Lerr;

	if (zs.avail_out != 0)
		debug stderr.writefln("Too little data in zlib stream: expected %d, got %d", destlen, destlen - zs.avail_out);

	return destbuf[0..$-zs.avail_out];
}
