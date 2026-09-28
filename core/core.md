## Standard library

In general, follow Zig's standard library; if something is missing, follow Go's.


From Zig, not incorporated:
	Build
	DynLib
	Options
	Progress
	Random
	RingBuffer
	SemanticVersion
	Target
	Thread
	Treap
	Tz
	builtin
	log
	debug
		dwarf
		pdb
	macho
	meta  -- Type introspection related
	start
	valgrind  -- Memory management issue detector
	zig  -- Zig compiler source itself (not meant for use from the language)
	     -- We could also consider making this usable from build.rg.

CHATGPT not incorporated:

 ├── os/
 │    ├── env
 │    ├── process
 │    ├── signals
 │    ├── fs
 │    └── ...
 ├── concurrency/
 │    ├── thread
 │    ├── sync
 │    ├── channel
 │    ├── atomic
 │    └── ...
 ├── reflect/  (if the language supports introspection/reflection)
 ├── debug/    (profilers, asserts ampliados, dumps, etc.)
 └── build/    (if there is a Zig/Go-style build script)


From Go std, not incorporated:

- context  -- For managing timeouts and cancellation signals in async operations

- debug

	- buildinfo
	- dwarf
	- elf
	- gosym
	- macho
	- pe
	- plan9obj

- expvar

- flag -- Command-line flag parsing

- go (the compiler and runtime)
    - ast
	- ...

- unique
- unsafe
- weak
