//-----------------------------------------------------------------------------
// CMurmurHash2A, by Austin Appleby

// This is a sample implementation of MurmurHash2A designed to work
// incrementally.

// Usage -

// CMurmurHash2A hasher
// hasher.Begin(seed);
// hasher.Add(data1,size1);
// hasher.Add(data2,size2);
// ...
// hasher.Add(dataN,sizeN);
// uint hash = hasher.End()

module murmurhash2a;

import std.conv;

struct MurmurHash2A
{
	private static string mmix(string h, string k) { return "{ "~k~" *= m; "~k~" ^= "~k~" >> r; "~k~" *= m; "~h~" *= m; "~h~" ^= "~k~"; }"; }


public:

	void Begin ( uint seed = 0 )
	{
		m_hash  = seed;
		m_tail  = 0;
		m_count = 0;
		m_size  = 0;
	}

	void Add ( const(void) * vdata, int len )
	{
		ubyte * data = cast(ubyte*)vdata;
		m_size += len;

		MixTail(data,len);

		while(len >= 4)
		{
			uint k = *cast(uint*)data;

			mixin(mmix("m_hash","k"));

			data += 4;
			len -= 4;
		}

		MixTail(data,len);
	}

	uint End ( )
	{
		mixin(mmix("m_hash","m_tail"));
		mixin(mmix("m_hash","m_size"));

		m_hash ^= m_hash >> 13;
		m_hash *= m;
		m_hash ^= m_hash >> 15;

		return m_hash;
	}

	// D-specific
	void Add(ref ubyte v) { Add(&v, v.sizeof); }
	void Add(ref int v) { Add(&v, v.sizeof); }
	void Add(ref uint v) { Add(&v, v.sizeof); }
	void Add(string s) { Add(s.ptr, to!uint(s.length)); }
	void Add(ubyte[] s) { Add(s.ptr, to!uint(s.length)); }

private:

	static const uint m = 0x5bd1e995;
	static const int r = 24;

	void MixTail ( ref ubyte * data, ref int len )
	{
		while( len && ((len<4) || m_count) )
		{
			m_tail |= (*data++) << (m_count * 8);

			m_count++;
			len--;

			if(m_count == 4)
			{
				mixin(mmix("m_hash","m_tail"));
				m_tail = 0;
				m_count = 0;
			}
		}
	}

	uint m_hash;
	uint m_tail;
	uint m_count;
	uint m_size;
};
