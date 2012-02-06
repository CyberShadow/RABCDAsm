/**
 * \file        lzma/version.h
 * \brief       Version number
 */

/*
 * Author: Lasse Collin
 *
 * This file has been put into the public domain.
 * You can do whatever you want with this file.
 *
 * See ../lzma.h for information about liblzma as a whole.
 */

module deimos.lzma_.version_;
import deimos.lzma;
import std.conv;

extern(C):

/*
 * Version number split into components
 */
enum LZMA_VERSION_MAJOR = 5;
enum LZMA_VERSION_MINOR = 0;
enum LZMA_VERSION_PATCH = 3;
enum LZMA_VERSION_STABILITY = LZMA_VERSION_STABILITY_STABLE;

/*
#ifndef LZMA_VERSION_COMMIT
#	define LZMA_VERSION_COMMIT ""
#endif*/
enum LZMA_VERSION_COMMIT = "";

/*
 * Map symbolic stability levels to integers.
 */
enum LZMA_VERSION_STABILITY_ALPHA = 0;
enum LZMA_VERSION_STABILITY_BETA = 1;
enum LZMA_VERSION_STABILITY_STABLE = 2;


/**
 * \brief       Compile-time version number
 *
 * The version number is of format xyyyzzzs where
 *  - x = major
 *  - yyy = minor
 *  - zzz = revision
 *  - s indicates stability: 0 = alpha, 1 = beta, 2 = stable
 *
 * The same xyyyzzz triplet is never reused with different stability levels.
 * For example, if 5.1.0alpha has been released, there will never be 5.1.0beta
 * or 5.1.0 stable.
 *
 * \note        The version number of liblzma has nothing to with
 *              the version number of Igor Pavlov's LZMA SDK.
 */
enum LZMA_VERSION = (LZMA_VERSION_MAJOR * 10000000U 
		+ LZMA_VERSION_MINOR * 10000U
		+ LZMA_VERSION_PATCH * 10U
		+ LZMA_VERSION_STABILITY);


/*
 * Macros to construct the compile-time version string
 */
static if(LZMA_VERSION_STABILITY == LZMA_VERSION_STABILITY_ALPHA)
	enum LZMA_VERSION_STABILITY_STRING = "alpha";
else static if(LZMA_VERSION_STABILITY == LZMA_VERSION_STABILITY_BETA)
	enum LZMA_VERSION_STABILITY_STRING = "beta";
else static if(LZMA_VERSION_STABILITY == LZMA_VERSION_STABILITY_STABLE)
	enum LZMA_VERSION_STABILITY_STRING = "";
else
	static assert(false, "Incorrect LZMA_VERSION_STABILITY");

/**
 * \brief       Compile-time version as a string
 *
 * This can be for example "4.999.5alpha", "4.999.8beta", or "5.0.0" (stable
 * versions don't have any "stable" suffix). In future, a snapshot built
 * from source code repository may include an additional suffix, for example
 * "4.999.8beta-21-g1d92". The commit ID won't be available in numeric form
 * in LZMA_VERSION macro.
 */
enum LZMA_VERSION_STRING = 
		to!string(LZMA_VERSION_MAJOR) ~ "." ~ to!string(LZMA_VERSION_MINOR) ~
		"." ~ to!string(LZMA_VERSION_PATCH) ~ LZMA_VERSION_STABILITY_STRING ~
		LZMA_VERSION_COMMIT;


/**
 * \brief       Run-time version number as an integer
 *
 * Return the value of LZMA_VERSION macro at the compile time of liblzma.
 * This allows the application to compare if it was built against the same,
 * older, or newer version of liblzma that is currently running.
 */
nothrow uint lzma_version_number();


/**
 * \brief       Run-time version as a string
 *
 * This function may be useful if you want to display which version of
 * liblzma your application is currently using.
 */
nothrow immutable(char)* lzma_version_string();
