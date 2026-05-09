<p align="center">
  <img src="logo.svg" alt="Argi Logo" width="200"/>
</p>

Argi is a general purpose programming language that aims to bridge the gap
between the convenience of high-level languages (Python, Julia...) and the
performance and control of low-level languages (C, Zig...).

It’s an early work-in-progress.


## Highlights

- 🧩 Consistency and simplicity.
- 🧮 Manual but very ergonomic memory management.
- 🎯 Explicitness without annoyance:
  - ⚠️ Side-effects are always explicit.
  - 🔐 Capability-based design for resource management.
  - 🪶 `reach` feature for reducing function signature clutter while
  maintaining explicitness.
- 🚫 No objects or inheritance.
- 🔀 Polymorphism through:
  - 🎛️ Multiple dispatch
  - ⚙️ Compile time parameters (rust's generics style)
  - 📜 Abstract types that are monomorphisized at compile time (rust's traits
  style)
  - 🎭 Virtual types for runtime dynamic dispatch.
- ❓ Errable and Nullable types.
- 📚 Batteries included. Two official module libraries: Minimalist `core` and
maximalist `more`.
- 🛠️ Tooling for building, testing, scaffolding, LSP, and a planned formatter
  (not in 0.1 yet).


## Repository structure

- 💭 Language design notes are in [`description/`](description/).
- ⚙️ The compiler source code is in [`src/`](src/) and is written in **Zig**,
targeting **LLVM**.
- 📚 The core library is in [`core/`](core/), and additional official libraries
are in [`more/`](more/).
- 🧪 Example programs and tests are in [`tests/`](tests/).


## Usage

### Building

Build a module by running:

```bash
argi build <root_dir>
```

### LSP

Start the language server:

```sh
argi lsp
```

### Scaffolding

Create a package manifest and basic ignore files for an importable folder
module:

```sh
argi init module my_module
```

Create a package manifest and a minimal application entrypoint:

```sh
argi init project my_project
argi build my_project/source/entrypoints/main
```


## Installation

### Platform support

Argi 0.1 is primarily tested on Linux and macOS.

Windows is not an official 0.1 target yet.

Building the compiler requires Zig 0.15.x and LLVM development files. The build
script looks for `llvm-config`, or you can set:

- `LLVM_INCLUDE_DIR`
- `LLVM_LIB_DIR`
- `LLVM_LIBS`

Building Argi programs also requires a C compiler/linker. By default Argi uses
`cc`. Set `CC=/path/to/compiler` to override it.

### Prerequisites

The build script needs to know where LLVM is installed. In restricted
environments, set the environment variables above instead of relying on
`llvm-config`.


### Compilation

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
project-local `.argi-cache/` directory. Normal build outputs stay explicit:
`argi build` still writes the final binary to `build/output` by default, or to
the path given with `--output`.

Tests are declared explicitly in source:

```rg
test my_test(.system: System = System()) -> !() := {
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
