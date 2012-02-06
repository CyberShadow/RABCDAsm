/**
 * \file        lzma/delta.h
 * \brief       Delta filter
 */

/*
 * Author: Lasse Collin
 *
 * This file has been put into the public domain.
 * You can do whatever you want with this file.
 *
 * See ../lzma.h for information about liblzma as a whole.
 */

module deimos.lzma_.delta;
import deimos.lzma;

extern(C):

/**
 * \brief       Filter ID
 *
 * Filter ID of the Delta filter. This is used as lzma_filter.id.
 */
enum LZMA_FILTER_DELTA = 0x03UL;


/**
 * \brief       Type of the delta calculation
 *
 * Currently only byte-wise delta is supported. Other possible types could
 * be, for example, delta of 16/32/64-bit little/big endian integers, but
 * these are not currently planned since byte-wise delta is almost as good.
 */
enum lzma_delta_type
{
	LZMA_DELTA_TYPE_BYTE
}


/**
 * \brief       Options for the Delta filter
 *
 * These options are needed by both encoder and decoder.
 */
struct lzma_options_delta
{
	/** For now, this must always be LZMA_DELTA_TYPE_BYTE. */
	lzma_delta_type type;

	/**
	 * \brief       Delta distance
	 *
	 * With the only currently supported type, LZMA_DELTA_TYPE_BYTE,
	 * the distance is as bytes.
	 *
	 * Examples:
	 *  - 16-bit stereo audio: distance = 4 bytes
	 *  - 24-bit RGB image data: distance = 3 bytes
	 */
	uint dist;
	enum LZMA_DELTA_DIST_MIN = 1;
	enum LZMA_DELTA_DIST_MAX = 256;

	/*
	 * Reserved space to allow possible future extensions without
	 * breaking the ABI. You should not touch these, because the names
	 * of these variables may change. These are and will never be used
	 * when type is LZMA_DELTA_TYPE_BYTE, so it is safe to leave these
	 * uninitialized.
	 */
	uint reserved_int1;
	uint reserved_int2;
	uint reserved_int3;
	uint reserved_int4;
	void *reserved_ptr1;
	void *reserved_ptr2;

}
