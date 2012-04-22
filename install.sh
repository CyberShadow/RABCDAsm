#!/bin/bash

PREFIX="/usr/local"
BUILDSCRIPT="build_rabcdasm.d"

if let UID!=0;
then {
    echo -e "You must run this script as root.";
    exit 5;
}; fi;

r="`dirname "$0"`"
d="$PREFIX/bin"

# Build RABCDasm
#dmd -run "$r/$BUILDSCRIPT" || exit $?

# Copy the executables
cp "$r/abcexport" "$d"
cp "$r/abcreplace" "$d"
cp "$r/rabcdasm" "$d"
cp "$r/rabcasm" "$d"
cp "$r/swfbinexport" "$d"
cp "$r/swfbinreplace" "$d"
cp "$r/swfdecompress" "$d"
cp "$r/swf7zcompress" "$d"
cp "$r/swflzmacompress" "$d"

