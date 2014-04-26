Javelin
=======
JVM 8, interpreting JVM 8 spec implementation in Haskell.

*Long term*
* Bytecode parser [**Done**]
* Runtime data structures [**In progress**]
* Linking/loading
* Execution (everything but invokedynamic & verification)
* Garbage collection
* Bytecode verification, invokedynamic

*Short term: Runtime data structures*
* Record pattern matching syntax
* More instructions, primitives: record patterns, data types, real implementations
return
exceptions
monitors
memory access
types of jvm and types of haskell (to correctly interpret arithmetics)

* Memory access for instructions
* Reference type, operations stack element size
* Chapters 3, 5 from JVM spec
* MVP: run a trivial main class
    * Write java Main class, compile, find out commands
    * Program commands
    * Program execution of commands
    * Write trivial class loading and what it takes to execute a static main method
* next: linking, general class loading, native api
    
*Javelin deferred tasks*
* need more unit testing for bytecode parser

*Possible offspring projects"
* UI for viewing bytecode
* Disassembler
* Decompiler?

*Haskell deferred tasks*
* cabal sandboxing
* quickcheck/hunit/tasty/hspec
* checkSpec, htest
* emacs modes
* hlint

*Java 7 -> 8 bytecode changes*
* 4.7.24, MethodParameters attribute (new)
* 4.7.20, RuntimeVisibleTypeAnnotations (new)
* 4.7.21, RuntimeInvisibleTypeAnnotations (new)
* Changes in descriptor and signatures terminology (refactoring)