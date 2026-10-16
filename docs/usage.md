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
`UIntNative`, booleans, records and fixed-size arrays by value, direct specialized
function calls, local assignments, `if`, `while`, `break`, `continue`, and bare `return`.
Boolean operators short-circuit. A program entry has no inputs and either no
result or `status_code: Int32`; its status follows native process truncation.

Array reads support nested values and returned temporaries. Writes follow local
storage through record fields and array indices, including nested combinations.
Copies are independent values, and all indexing checks bounds at runtime.

References, floating point, choices/errors, virtual calls, resources,
cleanup, globals, closures, foreign calls, and System capabilities are not yet
supported. Unsupported constructs in reachable function bodies are rejected
before execution, including constructs on untaken branches. Integer overflow,
division by zero, and `abort` produce source diagnostics. Overflow is currently
a checked VM failure; wrapping arithmetic and its equivalence across build modes
remain outside this subset.

Execution is limited to one million instructions, 128 nested calls, and one
million cumulative value cells. These are initial fixed limits, not a general
sandbox or a stable resource policy. No host I/O or native handles are exposed.
This command is an executor test surface; it does not implement `#run`, a REPL,
JIT compilation, frozen compile-time results, or execution caching.
