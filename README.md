<p align="center">
  <img src="logo.svg" alt="Argi Logo" width="200"/>
</p>

Argi is a general purpose programming language that aims to bridge the gap
between the convenience of high-level languages (Python, Julia...) and the
performance and control of low-level languages (C, Zig...).

It’s an early work-in-progress.


## Highlights

- 🧩 Consistency and simplicity.
- 🧮 Explicit memory allocation strategies through dependency injection.
- 🛡️ Automatic deterministic cleanup and temporal memory safety, with
  compile-time checks for value validity and reference lifetimes across moves,
  cleanup, and storage reuse.
- 🎯 Explicitness without annoyance:
  - ⚠️ Application-visible side effects are designed to be explicit.
  - 🔐 Capability-based design for resource management.
  - 🪶 `assume` for lexical implicit arguments and `reach` for propagating
    dependencies through intermediate calls.
- 🚫 No objects or inheritance.
- 🔀 Polymorphism through:
  - 🎛️ Multiple dispatch
  - ⚙️ Compile-time parameters (Rust's generics style)
  - 📜 Abstract types specialized at compile time (Rust's traits style)
  - 🎭 Virtual types for runtime dynamic dispatch.
- ❓ Errable and Nullable types, with nominal error reasons, reason-set
  inference, and explicit propagation with optional trace context.
- 📚 Two official module libraries: foundational `core` and domain-oriented
  `more`. Some modules remain design sketches; consult their implementations
  for supported APIs.
- 🛠️ Tooling for building, exhaustive checking, testing, scaffolding, and LSP.
  Source formatting remains planned.


## Repository structure

- 💭 Language design notes are in [`description/`](description/).
- ⚙️ The compiler source code is in [`src/`](src/) and is written in **Zig**,
targeting **LLVM**.
- 📚 The core library is in [`core/`](core/), and additional official libraries
are in [`more/`](more/).
- 🧪 Example programs and tests are in [`tests/`](tests/).


## Usage

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

| Command | Purpose |
| --- | --- |
| `argi build [dir]` | Compile the current package or a selected module. |
| `argi run` | Compile and run the default executable. |
| `argi check [dir]` | Check all function bodies, including unreachable ones. |
| `argi test [dir]` | Run language-level tests. |
| `argi lsp` | Start the language server. |

Use `--target aarch64-linux-gnu --just-emit-obj output.o` to emit a Linux
ARM64 object; the default target is native. `argi run` requires a compatible
native target.

Use `--release` with `build` or `run` for optimized executables. See `argi help`
for target selection, output paths, and LLVM/object emission options.

Packages declare executables in `argi.toml`; outputs go to
`build/debug/<name>`, including when selecting a declared entry module directly.
Standalone modules use `build/output`; test artifacts and reusable compiler
snapshots use `.argi-cache/`. Use `--no-cache` for a fresh frontend build and
`--stats` to inspect module reuse.
See [package configuration](description/02_modules.md) and
[language-level testing](description/72_testing.md).

The LSP provides diagnostics, semantic highlighting, hover, completion, and
navigation to definitions.

## Installation

### Binary packages

Download your platform's archive and `SHA256SUMS` from the
[latest release](https://github.com/endikallanomatxin/argi/releases/latest).
Linux x86_64/ARM64 and macOS Intel/Apple Silicon packages include the compiler,
core, and LLVM runtime. Extract the package and add its `bin` directory to
`PATH`, keeping `bin` and `lib` together.

You need a system C compiler/linker to build Argi programs, but no Zig or
separate LLVM installation. See the
[binary installation guide](.github/scripts/binary_installation.md) for supported
OS versions, checksum verification, and platform setup. Windows support is
planned.

### From source

Building the compiler requires Zig 0.16.x and LLVM 21 development files:

```sh
zig build                    # local installation in zig-out/
zig build -p ~/.local        # user installation, including core
export PATH="$HOME/.local/bin:$PATH"
```

LLVM is located through `llvm-config-21` or `llvm-config`; override paths with
`LLVM_INCLUDE_DIR`, `LLVM_LIB_DIR`, and `LLVM_LIBS` when needed. Argi uses `cc`
to link programs; set `CC` to select another compiler. `--sysroot` or
`ARGI_SYSROOT` can select another Argi installation prefix.

## Compiler tests

Run the compiler's regression suite with:

```sh
zig build test --summary all
```

## Release status

The latest experimental release is [0.2.0](releases/0.2.0.md).
`main` and annotated version tags contain published releases; `develop`
contains work for the next release. Breaking changes are expected.
