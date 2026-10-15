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
