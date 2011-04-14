RABCDAsm Changelog
==================

RABCDAsm v1.5 (2011.04.14)
--------------------------

 * Fixed v1.4 constant pool regression
 * Added support for memory-access and sign-extend opcodes
 * Speed optimizations
 * Documentation updates

RABCDAsm v1.4 (2011.03.07)
--------------------------

 * Source code ported to D2
 * Add support for forward-references for TypeName-kind Multinames
 * Correctly order classes by dependencies (extends/implements) and reference
   count
 * Finish Metadata support
 * Documentation updates

RABCDAsm v1.3 (2010.11.11)
--------------------------

 * Fixed double precision problem
   * This also fixes problems with illegal default values for function
     parameters (default values for integer parameters are stored as doubles, 
     which might become out-of-range due to inadequate double precision)
 * Added Changelog
 * Documentation markdown fixes

RABCDAsm v1.2 (2010.11.06)
--------------------------

 * Fixed ref generation for orphan objects which were only referenced
   by other orphans
 * Better error handling in `abcexport`; warn when no DoABC tags found
 * Documentation updates

RABCDAsm v1.1 (2010.06.30)
--------------------------

 * Private namespaces are now referenced by auto-generated names
 * Use `:` to delimit namespace and name in QNames for consistency
    * Warning: this breaks compatibility with v1.0 disassemblies
 * Fixed relative include paths
 * Add optional byte offsets to labels, which allows lossless representation
   of jumps inside instructions and outside the function bounds
 * Documentation updates

RABCDAsm v1.0 (2010.05.05)
--------------------------

 * Initial release.
