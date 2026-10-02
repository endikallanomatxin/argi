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

### Building

Build the natural target for the current module directory:

```bash
argi build
```

Build a specific module directory:

```bash
argi build <root_dir>
```

If the directory contains `argi.toml`, the tool uses its package configuration.
Executable packages declare build targets with `[executables.*]`:

```toml
[executables.hello]
path = "source/hello"

[run]
default = "hello"
```

Selecting a declared entry module directly, or building from that module's
directory, uses the same package output. The default output for package
executables is:

```text
build/debug/<executable-name>
```

Run the default executable with:

```bash
argi run
```

### Checking

Validate every function body in a module, including functions that a normal
executable build would leave unreachable:

```bash
argi check <root_dir>
```

Use `--release` with `build` or `run` for optimized machine code. `build` also
supports `--output <path>`, `--emit-llvm <path>`, `--emit-obj <path>`, and
`--just-emit-obj <path>`. See `argi help` for the complete CLI.

### LSP

Start the language server:

```sh
argi lsp
```

The server provides diagnostics, semantic highlighting, navigation, and basic
completion for visible names, function signatures, named arguments, and imported
module members. Field completion supports annotated types and direct constructor
initializers, including reference field chains.

### Scaffolding

Create an executable package:

```sh
argi init hello
cd hello
argi build
argi run
```

Without a name, `argi init` initializes the current directory and derives the
package and default executable name from its directory name. `argi init --lib`
likewise initializes a library in the current directory. Existing files are
preserved.

The generated entrypoint selects its allocator, error tracer, buffered output
writer, and input reader explicitly:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
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

Create a library/importable package with no executables:

```sh
argi init --lib math_utils
```


## Installation

### Binary distributions

Download a package and `SHA256SUMS` from the
[latest release](https://github.com/endikallanomatxin/argi/releases/latest).
Packages are available for Linux x86_64/ARM64 and macOS Intel/Apple Silicon,
with the compiler, core library, and LLVM runtime included. Extract the package
and add its `bin` directory to `PATH`; keep `bin` and `lib` together.

Zig and a separate LLVM installation are not required. You still need a system
C compiler/linker to build Argi programs. Linux packages require glibc 2.39 or
newer; macOS packages require macOS 15 or newer. See the
[binary installation guide](.github/scripts/binary_installation.md) for checksums and
platform setup.

### Building from source

#### Platform support

Native CI covers Linux and macOS.

Windows is not an official target yet.

Building the compiler requires Zig 0.16.x and LLVM 21 development files. When
several LLVM versions are installed, use `llvm-config-21` to set the paths.
The build script looks for `llvm-config`, or you can set:

- `LLVM_INCLUDE_DIR`
- `LLVM_LIB_DIR`
- `LLVM_LIBS`

Building Argi programs also requires a C compiler/linker. By default Argi uses
`cc`. Set `CC=/path/to/compiler` to override it.

#### Prerequisites

The build script needs to know where LLVM is installed. In restricted
environments, set the environment variables above instead of relying on
`llvm-config`.


#### Compilation

To build the tool in the repository-local `zig-out/` prefix:

```sh
zig build
```

That creates:

```text
zig-out/
├── bin/
│   └── argi
└── lib/
    └── argi/
        └── core/
```

For a normal user installation, install into a prefix such as `~/.local`:

```sh
zig build -p ~/.local
```

That installs:

```text
~/.local/
├── bin/
│   └── argi
└── lib/
    └── argi/
        └── core/
```

Make sure `~/.local/bin` is in your `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

The compiler resolves the required `core` library from the installation prefix,
so symlinking only the binary is not the recommended installation path.
`ARGI_SYSROOT=/path/to/prefix` and `--sysroot /path/to/prefix` are available as
development/debugging overrides when you need to point the compiler at a
specific Argi installation prefix.


Also, for recompiling and using the tool directly, you can run:

```bash
zig build run -- <arguments>
```


## Testing

Argi has native language-level tests.

Use:

```bash
./zig-out/bin/argi test tests/some_module
```

Generated test binaries and other transient testing artifacts live under the
project-local `.argi-cache/` directory. Package executable outputs live under
`build/debug/`. Explicit module-directory builds keep their legacy default
`build/output` path for now, or use the path given with `--output`.

Tests are declared explicitly in source:

```rg
test my_test(.system: System) -> !() := {
    testing.expect(true)!
}
```

Normal builds ignore `test` declarations:

```bash
./zig-out/bin/argi build tests/some_module
```

Compiler regression tests for Argi itself still run through Zig:

```bash
zig build test --summary all
```


## Safety scope

The compiler checks temporal validity and ownership effects. Core allocations,
initialized array views, and collection access provide checked bounded-storage
paths. Trusted low-level operations still require their callers to prove
physical storage obligations; arbitrary raw-pointer operations do not acquire
a general spatial-safety guarantee. Mutable references do not imply exclusive
access or concurrency safety. See [the safety model](description/34_safety_model.md)
and [allocation contracts](description/35_allocation.md).

## Release status

The `develop` branch prepares the `0.2.0` experimental release.
Published releases remain on `main` and their annotated version tags.

The language, compiler API, standard library layout, runtime model and tooling
are not stable yet. Breaking changes are expected.

See [releases/0.2.0.md](releases/0.2.0.md) for the prepared release notes and
[releases/0.1.0.md](releases/0.1.0.md) for the preceding release.
