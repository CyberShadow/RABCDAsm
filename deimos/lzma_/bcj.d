/**
 * \file        lzma/bcj.h
 * \brief       Branch/Call/Jump conversion filters
 */

/*
 * Author: Lasse Collin
 *
 * This file has been put into the public domain.
 * You can do whatever you want with this file.
 *
 * See ../lzma.h for information about liblzma as a whole.
 */

module deimos.lzma_.bcj;
import deimos.lzma;

extern(C):

/* Filter IDs for lzma_filter.id */

enum LZMA_FILTER_X86 = 0x04UL;
	/**<
	 * Filter for x86 binaries
	 */


enum LZMA_FILTER_POWERPC = 0x05UL;
	/**<
	 * Filter for Big endian PowerPC binaries
	 */

enum LZMA_FILTER_IA64 = 0x06UL;
	/**<
	 * Filter for IA-64 (Itanium) binaries.
	 */

enum LZMA_FILTER_ARM = 0x07UL;
	/**<
	 * Filter for ARM binaries.
	 */

enum LZMA_FILTER_ARMTHUMB = 0x08UL;
	/**<
	 * Filter for ARM-Thumb binaries.
	 */

enum LZMA_FILTER_SPARC = 0x09UL;
	/**<
	 * Filter for SPARC binaries.
	 */


/**
 * \brief       Options for BCJ filters
 *
 * The BCJ filters never change the size of the data. Specifying options
 * for them is optional: if pointer to options is NULL, default value is
 * used. You probably never need to specify options to BCJ filters, so just
 * set the options pointer to NULL and be happy.
 *
 * If options with non-default values have been specified when encoding,
 * the same options must also be specified when decoding.
 *
 * \note        At the moment, none of the BCJ filters support
 *              LZMA_SYNC_FLUSH. If LZMA_SYNC_FLUSH is specified,
 *              LZMA_OPTIONS_ERROR will be returned. If there is need,
 *              partial support for LZMA_SYNC_FLUSH can be added in future.
 *              Partial means that flushing would be possible only at
 *              offsets that are multiple of 2, 4, or 16 depending on
 *              the filter, except x86 which cannot be made to support
 *              LZMA_SYNC_FLUSH predictably.
 */
struct lzma_options_bcj
{
	/**
	 * \brief       Start offset for conversions
	 *
	 * This setting is useful only when the same filter is used
	 * _separately_ for multiple sections of the same executable file,
	 * and the sections contain cross-section branch/call/jump
	 * instructions. In that case it is beneficial to set the start
	 * offset of the non-first sections so that the relative addresses
	 * of the cross-section branch/call/jump instructions will use the
	 * same absolute addresses as in the first section.
	 *
	 * When the pointer to options is NULL, the default value (zero)
	 * is used.
	 */
	uint start_offset;
}
