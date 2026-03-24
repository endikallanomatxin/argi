<p align="center">
  <img src="logo.svg" alt="Argi Logo" width="200"/>
</p>

Argi is a general purpose programming language that aims to bridge the gap
between the convenience of high-level languages (Python, Julia...) and the
performance and control of low-level languages (C, Zig...).

It’s an early work-in-progress.

- 💭 Language design notes are in [`description/`](description/).
- ⚙️ The compiler is in [`compiler/`](compiler/) and is written in **Zig**,
targeting **LLVM**.


Highlights:

- Manual but very ergonomic memory management.
- Explicitness without annoyance:
    - Side-effects are always explicit.
    - Capability-based design for resource management.
    - `reach` feature for reducing function signature clutter while maintaining
    explicitness.
- No objects or inheritance.
- Polymorphism through:
    - Multiple dispatch
    - Generics
    - Abstract types (rust's traits style)
    - Virtual types (dynamic dispatch)
- Errable and Nullable types.
- Big core library.
- Great tooling (official formatter, lsp...).

## Prerequisites

The build script needs to know where LLVM is installed. Normally it attempts to
invoke `llvm-config` but this may fail in restricted environments. As an
alternative you can provide the paths manually via the following environment
variables before running `zig build`:

```
export LLVM_INCLUDE_DIR=/path/to/llvm/include
export LLVM_LIB_DIR=/path/to/llvm/lib
export LLVM_LIBS="$(llvm-config --libs)"
```

If these variables are set `llvm-config` will not be executed.

## Usage

### Build

Build the compiler:

```sh
zig build
```

That will create a binary called `argi` in the `zig-out/bin/` directory.

Then you can build a folder module by running:

```bash
./zig-out/bin/argi build tests/00_minimal_main
```

You can also run the compiler directly with:

```bash
zig build run -- build tests/00_minimal_main
```


### LSP

Start the language server:

```sh
./zig-out/bin/argi lsp
```

### Tests

You can run the tests in `test/` by doing:

```bash
zig build test --summary all
```

If testing doesn't work, the same can be checked by compiling the files
independently:

```bash
zig build
./zig-out/bin/argi build tests/00_minimal_main
```

