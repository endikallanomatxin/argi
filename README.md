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
- 🛠️ Great tooling (official formatter, lsp...).


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


## Installation

### Prerequisites

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


### Compilation

To build the tool:

```sh
zig build
```

That will create a binary called `argi` in the `zig-out/bin/` directory.

Yo can create a symlink to it in your `~/.local/bin/` (or any directory in your
PATH) to run it from anywhere:

```bash
ln -s "$(pwd)/zig-out/bin/argi" ~/.local/bin/argi
```

That way the editor will be able to find the tool for formatting and LSP
features, and you can run it from anywhere in the terminal as well.


Also, for recompiling and using the tool directly, you can run:

```bash
zig build run -- <arguments>
```


## Testing

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

