/**
 * \file        lzma/check.h
 * \brief       Integrity checks
 */

/*
 * Author: Lasse Collin
 *
 * This file has been put into the public domain.
 * You can do whatever you want with this file.
 *
 * See ../lzma.h for information about liblzma as a whole.
 */

module deimos.lzma_.check;
import deimos.lzma;

extern(C):

/**
 * \brief       Type of the integrity check (Check ID)
 *
 * The .xz format supports multiple types of checks that are calculated
 * from the uncompressed data. They vary in both speed and ability to
 * detect errors.
 */
enum lzma_check
{
	LZMA_CHECK_NONE     = 0,
		/**<
		 * No Check is calculated.
		 *
		 * Size of the Check field: 0 bytes
		 */

	LZMA_CHECK_CRC32    = 1,
		/**<
		 * CRC32 using the polynomial from the IEEE 802.3 standard
		 *
		 * Size of the Check field: 4 bytes
		 */

	LZMA_CHECK_CRC64    = 4,
		/**<
		 * CRC64 using the polynomial from the ECMA-182 standard
		 *
		 * Size of the Check field: 8 bytes
		 */

	LZMA_CHECK_SHA256   = 10
}


/**
 * \brief       Maximum valid Check ID
 *
 * The .xz file format specification specifies 16 Check IDs (0-15). Some
 * of them are only reserved, that is, no actual Check algorithm has been
 * assigned. When decoding, liblzma still accepts unknown Check IDs for
 * future compatibility. If a valid but unsupported Check ID is detected,
 * liblzma can indicate a warning; see the flags LZMA_TELL_NO_CHECK,
 * LZMA_TELL_UNSUPPORTED_CHECK, and LZMA_TELL_ANY_CHECK in container.h.
 */
enum LZMA_CHECK_ID_MAX = 15;


/**
 * \brief       Test if the given Check ID is supported
 *
 * Return true if the given Check ID is supported by this liblzma build.
 * Otherwise false is returned. It is safe to call this with a value that
 * is not in the range [0, 15]; in that case the return value is always false.
 *
 * You can assume that LZMA_CHECK_NONE and LZMA_CHECK_CRC32 are always
 * supported (even if liblzma is built with limited features).
 */
nothrow lzma_bool lzma_check_is_supported(lzma_check check);


/**
 * \brief       Get the size of the Check field with the given Check ID
 *
 * Although not all Check IDs have a check algorithm associated, the size of
 * every Check is already frozen. This function returns the size (in bytes) of
 * the Check field with the specified Check ID. The values are:
 * { 0, 4, 4, 4, 8, 8, 8, 16, 16, 16, 32, 32, 32, 64, 64, 64 }
 *
 * If the argument is not in the range [0, 15], UINT32_MAX is returned.
 */
nothrow uint lzma_check_size(lzma_check check);


/**
 * \brief       Maximum size of a Check field
 */
enum LZMA_CHECK_SIZE_MAX = 64;


/**
 * \brief       Calculate CRC32
 *
 * Calculate CRC32 using the polynomial from the IEEE 802.3 standard.
 *
 * \param       buf     Pointer to the input buffer
 * \param       size    Size of the input buffer
 * \param       crc     Previously returned CRC value. This is used to
 *                      calculate the CRC of a big buffer in smaller chunks.
 *                      Set to zero when starting a new calculation.
 *
 * \return      Updated CRC value, which can be passed to this function
 *              again to continue CRC calculation.
 */
nothrow pure uint lzma_crc32(
		const(ubyte)* buf, size_t size, uint crc);


/**
 * \brief       Calculate CRC64
 *
 * Calculate CRC64 using the polynomial from the ECMA-182 standard.
 *
 * This function is used similarly to lzma_crc32(). See its documentation.
 */
nothrow pure ulong lzma_crc64(
		const(ubyte)* buf, size_t size, ulong crc);


/*
 * SHA-256 functions are currently not exported to public API.
 * Contact Lasse Collin if you think it should be.
 */


/**
 * \brief       Get the type of the integrity check
 *
 * This function can be called only immediately after lzma_code() has
 * returned LZMA_NO_CHECK, LZMA_UNSUPPORTED_CHECK, or LZMA_GET_CHECK.
 * Calling this function in any other situation has undefined behavior.
 */
nothrow lzma_check lzma_get_check(const lzma_stream *strm);
