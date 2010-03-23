Robust ABC (ActionScript Bytecode) [Dis-]Assembler
==================================================

RABCDAsm is a collection of utilities including an ActionScript 
assembler/disassembler, and a few utilities to manipulate SWF files. 
These are:

 * `rabcdasm` - ABC disassembler
 * `rabcasm` - ABC assembler
 * `abcexport` - extracts ABC from SWF files
 * `abcreplace` - replaces ABC in SWF files
 * `swfdecompress` - decompresses zlib-compressed SWF files

`abcexport` and `abcreplace` are reimplementations of similar utilities from
my [`swfutilsex`][swfutilsex] Java package, however these work faster as they 
do not parse the SWF files as deeply.  
`swfdecompress` is ancilliary and is only useful for debugging and studying of
the SWF file format, and not required for ABC manipulation. It is functionally
equivalent to [flasm][]'s `-x` option.

  [swfutilsex]: http://github.com/CyberShadow/swfutilsex
  [flasm]: http://flasm.sourceforge.net/

Motivation and goals
--------------------

This package was created due to lack of similar software out there. 
Particularly, I needed an utility which would allow me to edit ActionScript
bytecode with the following properties:

 1. Speed. Less waiting means more productivity. `rabcasm` can assemble large
    projects (>200000 LOC) in under a second on modern machines.
 2. Comfortably-editable output. Each class is decompiled to its own file, with
    files arranged in subdirectories representing the package hierarchy. Class
    files are `#include`d from the main file.
 3. Most importantly - robustness! If the Adobe AVM can load and run the file,
    then it must be editable - no matter if the file is obfuscated or otherwise
    mutilated to prevent reverse-engineering. RABCDAsm achieves this by using
    a textual representation closer to the ABC file format, rather than to what
    an ActionScript compiler would generate.

Compiling
---------

RABCDAsm is written in the [D programming language, version 1][d1]. It uses one 
third-party library, [std2][] (for some fancy template stuff).

Compiling should be straight-forward: 

    dmd rabcdasm abcfile asprogram disassembler murmurhash2a
    dmd rabcasm  abcfile asprogram    assembler murmurhash2a
    dmd abcexport     swffile
    dmd abcreplace    swffile
    dmd swfdecompress swffile

  [d1]: http://www.digitalmars.com/d/1.0/
  [std2]: http://dsource.org/projects/std2

Usage
-----

To begin hacking on a SWF file:

    abcexport file.swf

This will create `file0.abc` ... `fileN.abc` (often just `file0.abc`). Each 
file corresponds to an ABC block inside the SWF file.

To disassemble one of the `.abc` files:

    rabcdasm file0.abc

This will create a `file0` directory, which will contain `file0.main.asasm`
(the main program file) and a file per ActionScript class.

To assemble the `.asasm` files back, and update the SWF file:

    rabcasm file0/file0.main.asasm
    abcreplace file0.swf 0 file0/file0.main.abc

Syntax
======

The syntax of the disassembly was designed to be very simple and allow fast 
and easy parsing. It is a close representation of the `.abc` file format, and 
thus it is somewhat verbose. All constant pool elements (signed/unsigned 
integers, doubles, strings, namespaces, namespace sets, multinames) are always 
*expanded inline*, for ease of editing. Similarly, classes, instances, methods
and method bodies are also defined inline, in the context of their "parent"
object. By-index references of classes and methods (used in the `newclass`, 
`newfunction` and `callstatic` instructions) are represented via 
automatically-generated unique "reference strings", declared as `refid` fields.

If you haven't yet, I strongly recommend that you look through Adobe's
[ActionScript Virtual Machine 2 (AVM2) Overview][avm2]. You will most likely
need to consult it for the instruction reference anyway (although you can also 
use [this handy list][avm2i] as well). You will find it difficult to understand
the disassembly without good understanding of concepts such as namespaces and
multinames.

  [avm2]: http://www.adobe.com/devnet/actionscript/articles/avm2overview.pdf
  [avm2i]: http://www.anotherbigidea.com/javaswf/avm2/AVM2Instructions.html

Overview
--------

In order to guarantee unambiguity and data preservation, all strings read from
the input file - including identifiers (variable/function/class names) - are 
represented as string literals. Thus, the syntax does not have any "reserved
words" or such - an unrecognized word is treated as an error, not as an 
identifier.

Whitespace (outside string literals, of course) is completely ignored, except 
where required to separate words. Comments are Intel-assembler-style: a single 
`;` demarks a comment until the next end-of-line. Control directives (such as
`#include`) are allowed anywhere where whitespace is allowed.

The syntax is comprised of hierarchical blocks. Each block contains a number
of fields - starting with a keyword specifying the field type. A block is 
terminated with the `end` keyword. Some fields contain a limited number of
parameters, and others are, or contain blocks.

Hierarchy
---------

The topmost block in the hierarchy is the `program` block. This must be the 
first block in the file (thus, `program` must be the first word in the file as
well). The `program` block contains `script` fields, and `class` / `method` 
fields for "orphan" classes and methods (not owned by other objects in the 
hierarchy). Orphan methods are usually anonymous functions. The file version is
also specified in the `program` block, using the `minorversion` and 
`majorversion` fields (both unsigned integers).

`script` blocks have one mandatory `sinit` field (the script initialization 
method) and `trait` fields.

A "trait" can be one of several kinds. The kind is specified right after the
`trait` keyword, followed by the trait name (a multiname). Following the name
are the trait fields, varying by trait kind:

 * `slot` / `const` : `slotid` (unsigned integer), `type` (multiname), `value`
 * `class` : `slotid`, `class` (the actual class block)
 * `function` : `slotid`, `method` (the actual method block)
 * `method` / `getter` / `setter` : `dispid` (unsigned integer), `method`

Additionally, all traits may have `flag` fields, describing the trait's 
attributes (`FINAL` / `OVERRIDE` / `METADATA`).

`class` blocks have mandatory `instance` and `cinit` fields, defining the class
instance and the class initializer method respectively. They may also have 
`trait` fields and a `refid` field (the `refid` field is not part of the file 
format - it's an unique string to allow referencing the class, see above).

`instance` blocks - always declared inline of their `class` block - must 
contain one `iinit` field (the instance initializer method), and may contain 
one `extends` field (multiname), `implements` fields (multinames), `flag` 
fields (`SEALED` / `FINAL` / `INTERFACE` / `PROTECTEDNS`), one `protectedns` 
field (namespace), and `trait` fields.

`method` blocks may contain one `name` field (multiname), a `refid` field,
`param` fields (multinames - this represents the parameter types), one
`returns` field (multiname), `flag` fields (`NEED_ARGUMENTS` / 
`NEED_ACTIVATION` / `NEED_REST` / `HAS_OPTIONAL` / `SET_DXNS` / 
`HAS_PARAM_NAMES`), `optional` fields (values), `paramname` fields (strings), 
and a `body` field (method body).

`body` blocks - always declared inline of their `method` block - must contain
the `maxstack`, `localcount`, `initscopedepth` and `maxscopedepth` fields 
(unsigned integers), and a `code` field. It may also contain `try` and `trait`
fields.

`code` blocks - always declared inline of their `body` block - are somewhat 
different in syntax from other blocks - mostly in that they may contain labels.
Labels follow the most common syntax - a word followed by a `:` character. 
Multiple instruction arguments are comma-separated. Instruction arguments'
types depend on the instruction - see the `OpcodeInfo` array in `abcfile.d`
for a reference.

`try` blocks - always declared inline of their `body` block - represent an
"exception" (try/catch) block. They contain five mandatory fields: `from`,
`to` and `target` (names of labels representing start and end of the "try"
block, and start of the "catch" block respectively), and `type` and `name` 
(multinames), representing the type and name of the exception variable.

Values have the syntax *type* `(` *value* `)` . *type* can be one of `Integer`,
`UInteger`, `Double`, `Utf8`, `Namespace`, `PackageNamespace`, 
`PackageInternalNs`, `ProtectedNamespace`, `ExplicitNamespace`, 
`StaticProtectedNs`, `PrivateNamespace`, `True`, `False`, `Null` or 
`Undefined`. The type of the value depends on *type*. Types `True`, `False`, 
`Null` and `Undefined` have no value.

Constants
---------

Multinames have the syntax *type* `(` *parameters* `)` . *type* can be one of 
`QName` / `QNameA`, `RTQName` / `RTQNameA`, `RTQNameL` / `RTQNameLA`, 
`Multiname` / `MultinameA`, `MultinameL` / `MultinameLA`, or `TypeName`.
*parameters* depends on *type*:

 * `QName` / `QNameA` `(` *namespace* `,` *string* `)`
 * `RTQName` / `RTQNameA` `(` *string* `)`
 * `RTQNameL` / `RTQNameLA` `(` `)`
 * `Multiname` / `MultinameA` `(` *string* `,` *namespace-set* `)`
 * `MultinameL` / `MultinameLA` `(` *namespace-set* `)`
 * `TypeName` `(` *multiname* `<` *multiname [* `,` *multiname ... ]* `>` `)`

Namespace sets have the syntax `[` *[ namespace [* `,` *namespace ... ] ]* `]`
(that is, a comma-separated list of namespaces in square brackets). Empty
namespace sets can be specified using `[]`.

Namespaces have the syntax *type* `(` *parameters* `)` . For types other than
`PrivateNamespace` there is only one parameter - a string. `PrivateNamespace`
namespaces have a second parameter - an integer to distinguish this private
namespace from others.

Strings have a syntax similar to C string literals. Strings start and end with
a `"`. Supported escape sequences (a backslash followed by a letter) are `\n`
(generates ASCII 0x0A), `\r` (ASCII 0x0D), and `\x` followed by two hexadecimal
digits, which inserts the ASCII character with that code. Any other characters
following a backslash generate that character - thus, you can escape 
backslashes using `\\` and double quotes using `\"`. When decompiling, 
high-ASCII characters (usually UTF-8) are not escaped - if you see gibberish 
instead of international text, configure your editor to open the files in UTF-8
encoding.

Additionally, constant pool types (signed/unsigned integers, doubles, strings,
namespaces, namespace sets and multinames) may also have the value `null`
(which represents the index 0 in the ABC file). Note that `null` is 
conceptually different from zero, an empty string or empty namespace set.

Macros
------

RABCDAsm has some basic macro-like capabilities, controlled by directives and 
variables. These bear some similarity to the C preprocessor, however these 
are processed in-loop rather than as a separate pre-processing step.

### Directives

Directives start with a `#`, followed by a word identifying the directive:

  * `#include` *string* - inserts the contents of the file by the specified
    filename inline. Functionally equivalent to `#mixin #get` *string* , but 
    faster.
  * `#mixin` *string* - inserts the contents of the specified string inline.
    Not very useful on its own.
  * `#call` *string* `(` *[ string [* `,` *string ... ] ]* `)` - same as 
    `#mixin`, however it additionally sets the special variables `$1`, `$2` 
    etc. to the contents of the specified arguments. When the end of the 
    inserted string is reached, the old values of `$1`, `$2` etc. are restored.
  * `#get` *string* - inserts **a string containing** the contents of the 
    file by the specified filename inline. Similar to #include, but it inserts
    a string (surrounded by `"` etc.) instead.
  * `#set` *word* *string* - assigns the contents of the string to the 
    variable *word*.
  * `#unset` *word* - deletes the variable *word*.

### Variables

Variables are manipulated with the `#set` and `#unset` directives, and can
be instantiated in two ways:

  1. `$`*name* - this inserts the contents of the variable inline. Note that
     although variables are defined using a string syntax, they are not 
     inserted as a string using this syntax. Thus, the code:

        #set str "Hello, world!"
        ...
        pushstring $str

     will expand to `pushstring Hello, world!`, which will result in an error.
     To correct the problem, add escaped quotes around the variable contents
     ( `#set str "\"Hello, world!\""` ), or use the second syntax:
  
  2. `$"`*name*`"` - this inserts a string containing the contents of the 
     variable inline. This syntax also works for `#call` arguments (e.g. 
     `$"1"`).

### Example

Here's an example of how to use the above features to create a macro which
logs a string literal and the contents of a register:

     #set log "
         findpropstrict      QName(PackageNamespace(\"\"), \"log\")
         pushstring          $\"1\"
         getlocal            $2
         callpropvoid        QName(PackageNamespace(\"\"), \"log\"), 2
     "
     
     ; ...
     
     pushbyte 2
     pushbyte 2
     add_i
     setlocal1
     #call $"log"("two plus two equals", "1")
     
Highlighting
------------

Included with the project is the file `asasm.hrc`, a simple syntax definition 
for the [Colorer take5][] syntax highlighting library. It should be 
straigth-forward to adapt it to other syntax highlighting systems.

  [Colorer take5]: http://colorer.sourceforge.net/

Limitations
===========

Metadata is currently ignored. I haven't noticed any metadata blocks in any
Flash applications I've disassembled.

License
=======

RABCDAsm is distributed under the terms of the GPL v3 or later, with the
exception of `murmurhash2a.d`, which is in the public domain, and `asasm.hrc`,
which is tri-licensed under the MPL 1.1/GPL 2.0/LGPL 2.1. The full text of the
GNU General Public License can be found in the file `COPYING`.
