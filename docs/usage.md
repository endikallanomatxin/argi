# Using Argi

## Creating a project

Create and run a program:

```sh
argi init hello
cd hello
argi run
```

`argi init` without a name initializes the current directory; `argi init --lib`
creates a library. Existing files are preserved. The generated entrypoint
sets up allocator, error tracing, and I/O capabilities:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi ::= system.ffi
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    assume error_tracer ::= FixedSizeErrorTracer(
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    ) | to_virtual#(ErrorTracer)($&_) | $&_
    assume writer ::= $&BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout,
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    )
    assume reader ::= $&system.terminal&.stdin
}
```

## Commands

| Command | Purpose |
| --- | --- |
| `argi build [dir]` | Compile the current package or a selected module. |
| `argi run` | Compile and run the default executable. |
| `argi run --vm <directory>` | Run the experimental scalar/aggregate bytecode subset. |
| `argi check [dir]` | Check all function bodies, including unreachable ones. |
| `argi test [dir]` | Run language-level tests. |
| `argi lsp` | Start the language server. |

Use `--release` with `build` or `run` for optimized executables. See `argi help`
for target selection, output paths, and LLVM/object emission options.

## Packages and build outputs

Packages declare executables in `argi.toml`; outputs go to
`build/debug/<name>`, including when selecting a declared entry module directly.
Standalone modules use `build/output`; test artifacts and reusable compiler
snapshots use `.argi-cache/`. Use `--no-cache` for a fresh frontend build and
`--stats` to inspect module reuse.
See [package configuration](../description/02_modules.md) and
[language-level testing](../description/72_testing.md).

## Formatting and editor support

The LSP provides diagnostics, semantic highlighting, hover, completion,
document symbols, and navigation to definitions.

Run `argi format [paths...]` to format files or directories,
`argi format --check [paths...]` to check without writing, or
`argi format file.rg --stdout` to preview a file. Editors can request document
formatting through `argi lsp`.

See the [source formatting rules](../description/01_source_formatting.md).

## Cross-compilation

Use `--target aarch64-linux-gnu --just-emit-obj output.o` to emit a Linux
ARM64 object; the default target is native. `argi run` requires a compatible
native target. For an ARM64 executable, select a target-configured driver with
`--cc aarch64-linux-gnu-gcc`. `--cc-arg` supplies individual driver arguments
and `--c-sysroot` selects its C sysroot; `--sysroot` still selects Argi core.

## Toolchains and installation paths

Argi uses `cc` (`gcc` on Windows) to link programs. Set `CC` to choose another
compiler. `--sysroot` or `ARGI_SYSROOT` selects another Argi installation prefix;
this is separate from the C toolchain's `--c-sysroot`.

For installation, see the [binary guide](../.github/scripts/binary_installation.md)
or [building from source](../CONTRIBUTING.md#building-from-source).

## Experimental bytecode execution

`argi run --vm <directory>` uses the ordinary frontend, contract selection, and
safety checker, then lowers reachable checked functions to verified bytecode.
It does not emit LLVM, link a binary, or execute unsupported calls natively.
The directory is a folder module; package executable selection and ordinary
build flags are not supported in this mode. `--frontend-jobs N` is accepted.

The initial subset supports fixed-width integers through 64 bits, host-width
`UIntNative`, booleans, string literals, records and fixed-size arrays by value, direct specialized
function calls, local assignments, `if`, `while`, `for`, `break`, `continue`, and
bare `return`. Calls support multiple named outputs through their checked record
result. Boolean operators short-circuit. A program entry has no inputs and either no
result or `status_code: Int32`; its status follows native process truncation.

String literals use immutable UTF-8 backing owned by the execution context,
shared across repeated literals and valid after calls return. `StringView` values
can remain in interactive bindings; reset retires their backing with the context.
Checked reference offsets retain storage identity and enforce concrete bounds.
Text operations that require tracing or other capabilities still require those
capabilities and their bytecode operations to be supported.

Array reads support nested values and returned temporaries. Writes follow local
storage through record fields and array indices, including nested combinations.
Copies are independent values, and all indexing checks bounds at runtime.
Local safe references can be passed to and returned from checked calls. They retain
storage identity through record/array projections and can reduce mutable access
to read access. Ended call frames cannot be accessed. References cannot be supplied
as external VM inputs, and results cannot borrow a completed frame. Lexical lifetime
and aliasing rules remain the responsibility of the ordinary safety checker.

Choices support construction, tag tests, active-payload access and `match`,
including borrowed payloads. The verifier checks variant membership and payload
types; execution checks that a payload is active before reading or writing it.
`for` invokes the ordinary selected iterator operations, including borrowed array
iteration and scalar ranges when their checked bodies fit the VM subset.

Automatic cleanup uses the frontend's selected `Deinit` operations, including
scope exits, `return`, loop transfers, structural fields, and active choice payloads.
Whole and partial moves cancel the corresponding source cleanup. Explicit destruction
and outcome-dependent consumption update the same cleanup flags, even for discarded
call results. Destructors must themselves fit the supported execution subset.
Replacing a whole local binding or a statically identified local record field
evaluates the new value before cleaning up the old one. Constant local aliases
of those destinations use the same cleanup, including chains of aliases. The first
initialization does not run a destructor; neighboring fields retain their cleanup.
Explicit destruction followed by definite whole-value reinitialization also works
through reference parameters and reference fields in by-value argument records.
Scalar locals and outputs can be initialized through checked references before
their first read. Function output records and local records support independent
initialization of nested fields, including writes through references to those
fields. Reading a record requires all its fields; initialized siblings can be
read before the record is complete.
Local record storage is cleared on each lexical entry, including loop iterations.
Completing an owning record field by field activates its selected destructor.
An incomplete record instead cleans its initialized owning fields, including on
early exits; it never calls a destructor requiring the absent whole value.
Earlier copies retain their old lifetime and cannot be used again. General owning
replacement through unresolved or retargetable references and indexed storage
remains unsupported. Scalar and borrowed-only writes through references work.

Unary virtual values retain their concrete receiver and the immutable bytecode
unit containing the selected operations. Calls use that evidence directly, including
across REPL submissions; they do not run contract resolution at runtime. Receiver
permissions and storage liveness remain checked. Virtual values cannot escape the
executor as compile-time constants.

`error_location_id()` registers source coordinates in the execution context.
Retained REPL IDs keep their original submitted text across later commands; reset
clears them. These IDs cannot be exported as compile-time constants.
`source_location()` resolves those IDs to immutable path, line text and coordinates.
Unknown IDs stop execution. Error propagation (`!`) preserves the original tracer,
converts reason sets and runs checked early-return cleanup. Context propagation
(`!!`) with a `StringView` evaluates its context only on error and calls the
ordinary core trace helper. `FixedSizeErrorTracer` can record and reset contexts
using its caller-provided byte buffer; complete reporting still needs writer support.

Trusted reinterpretation of initialized integer records and arrays as `UInt8`
views preserves the original storage, permissions and target byte order. Byte
writes update the numeric value without creating cleanup obligations. Reference
fields and nonnumeric representations remain unsupported.

Referenced globals with constant initializers receive context-owned storage.
Dependencies follow the native initializer plan. Retained REPL globals initialize
once per session and preserve writes across later code units; reset starts fresh.
Globals requiring cleanup and globals without explicit initializers remain rejected.

Embedding hosts can register explicit integer-only foreign-call adapters with
`Vm.initWithHost` or a retained context's `host_bindings` (up to 32 integer
inputs and outputs). Symbols and complete integer signatures must match; missing
or ambiguous adapters reject a command before publication. The logical `ffi`
capability remains checked by the frontend.
Callbacks receive integer copies, and results are range-checked before publication.
Callback failures poison execution. `argi repl` registers stdout/stderr adapters;
`argi run --vm` currently registers none. Compile-time evaluation continues to
reject foreign calls.

Raw pointers, C enums, floating point, complete trace reporting,
partial choice initialization, vacant arrays with owning elements, owning globals,
closures,
general foreign calls,
and System capabilities are not yet supported. Unsupported constructs in reachable
function bodies are rejected
before execution, including constructs on untaken branches. Integer arithmetic
wraps at the declared width, matching native execution and constant evaluation.
Division rounds towards zero; `%` is the signed remainder. The signed minimum
divided by -1 wraps to itself, with remainder zero. Division by zero and `abort`
produce source diagnostics. These failures stop execution without running user
destructors; normal lexical cleanup is distinct from abort recovery.

Explicit `#run function(...)` calls use the same executor during compilation,
including native builds. Arguments must be constants; results freeze into compiler
values. References and values requiring cleanup cannot be exported. Compile-time
integer results can supply type shapes and compile-time parameters through staged
semantic resolution. Computed `#if` in function bodies uses the same evaluator;
only the selected arm is materialized for each specialization. See [compile-time computation](../description/50_comptime.md).

Execution is limited to one million instructions, 128 nested calls, and one
million cumulative value cells. These are initial fixed limits, not a general
sandbox or a stable resource policy. No host I/O or native handles are exposed.
`--vm` selects runtime execution; `#run` and computed conditions execute during
compilation regardless of that option. JIT remains deferred.

## Experimental persistent REPL

Run `argi repl` to load core and start a retained bytecode session. The same VM
subset and execution limits described above apply. `--sysroot <path>` selects an
installation prefix. Input can come from a terminal or a pipe.
At startup, ordinary checked Argi statements create a buffered `error_tracer`.
The terminal displays that prelude; `:reset` cleans the session and executes it
again. The prelude also acquires `ffi` and `Terminal`, borrowing stdout as `writer`,
so `print("hola")` works directly. Allocator capabilities are not supplied yet.
In a terminal, Up/Down recall earlier lines and restore the unfinished draft.
Recalled lines can be edited before submission; Ctrl-C cancels the current line
and Ctrl-D on an empty line exits. History lasts for the current REPL process.

`once` consumption is checked across accepted submissions, including calls through
ordinary helpers. Rejected candidates consume nothing, and reset starts a fresh
consumption history. Compile-time evaluation still rejects `once` calls.

Top-level `assume` declarations remain available to calls and selected cleanup in
later submissions. Inner blocks keep lexical assumptions local. Rejected
submissions publish no assumptions; reset clears the session evidence. References
to expression temporaries retain their backing storage until checked session
cleanup, including temporaries created by `assume capability ::= $&acquire()`.
Diagnostics identify unavailable reached inputs in generic calls as well.

```text
>>> value ::= 40 + 2
>>> value
_0 = 42
>>> answer := () -> (.result: Int32) { result = 7 }
>>> answer()
_1 = 7
>>> _0 + _1
_2 = 49
```

Each line is one submission. Use `:begin` and `:end` around multiline definitions
or statement blocks. Submit definitions separately from executable statements.
Functions, types and contracts remain available to subsequent submissions;
redefining accepted names is rejected. Imports use the normal folder-module loader;
relative paths start at the directory where the REPL was launched. Dependencies
are retained across submissions and reimports; reset allows fresh source loading.

Expressions create ordinary numbered bindings (`_0`, `_1`, ...), skipping names
already in use. Results, owners and loans remain in the session until reset or
exit; presentation does not copy owners or dereference references. Aggregate
presentation is bounded, StringView results display quoted text, other references
are shown as `<reference>`, and choices use
variant indexes. This is an initial value display, not the text-formatting API.

Scalar, record and non-owning array bindings can be declared without an initial
value and written in later commands. Initialized fields and elements can be read
independently of vacant siblings. A complete aggregate can be read once every
field or statically identified element is initialized, including nested fields.
Empty aggregates require an explicit write. Reads of unavailable storage are
rejected before publication. Array layouts keep one element template; concrete
execution cells are charged against the VM's memory limit before allocation.

`:reset` runs checked cleanup and starts a fresh session; `:quit` or EOF cleans up
and exits. Preparation failures publish no state and subsequent input can retry.
Diagnostics for wrapped statements and expression results point to the submitted
text. Unsupported bytecode operations report their source location.
A runtime trap retains any writes already executed and poisons the session; use
`:reset` before continuing. Trapped code cannot be safely unwound. No System/FFI
capabilities or native calls are implicitly granted by the REPL.
