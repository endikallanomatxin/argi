## Standard library

En general, copiemos la de zig, y si algo no está, copiemos la de go.


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
	     -- Igual podríamos hacer que sí estuviera pensado para ser usando desde build.rg

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
 ├── reflect/  (si tu lenguaje tiene introspección/reflexión)
 ├── debug/    (profilers, asserts ampliados, dumps, etc.)
 └── build/    (si tienes un “build script” estilo Zig/Go)


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

