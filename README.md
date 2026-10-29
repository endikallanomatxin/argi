<p align="center">
  <img src="logo.svg" alt="Argi Logo" width="200"/>
</p>

Argi is a general purpose programming language that aims to bridge the gap
between the convenience of high-level languages (Python, Julia...) and the
performance and control of low-level languages (C, Zig...), with compile-time
guarantees for memory safety and resource management.

It’s an early work-in-progress.


## Highlights

- 🧩 Consistency and simplicity.
- 🧮 Explicit memory allocation strategies through dependency injection.
- 🛡️ Automatic deterministic cleanup and temporal memory safety, with
  compile-time checks for value validity and reference lifetimes across moves,
  cleanup, and storage reuse.
- 🎯 Explicitness without annoyance:
  - ⚠️ Side effects are explicit.
  - 🔐 Capability-based design for resource management.
  - 🪶 `assume` for lexical implicit arguments, with dependencies declared in signatures.
- 🚫 No objects or inheritance.
- 🔀 Polymorphism:
  - ⚙️ Compile-time parameters specialize types and functions.
  - 📜 Contracts specify operations and requirements for one or more types.
    Implementations explicitly fulfill those requirements. More specific
    implementations can provide specialized behavior.
  - 🎭 Virtual types provide runtime dispatch.
- ❓ Errable and Nullable types make errors and missing values explicit.
- 📚 Two official module libraries: foundational `core` and domain-oriented
  `more`.
- 🛠️ Built-in tools for building, checking, testing, project scaffolding,
  formatting, and editor support through LSP.


## Installation

Download a [release package](https://github.com/endikallanomatxin/argi/releases/latest)
for Linux or macOS on x86_64 or ARM64. Extract it and add its `bin` directory to
`PATH`, keeping `bin` and `lib` together. A system C compiler/linker is required;
Zig and a separate LLVM installation are not.

See the [binary installation guide](.github/scripts/binary_installation.md) for
platform requirements and setup. To build from source, including on Windows,
see [CONTRIBUTING.md](CONTRIBUTING.md#building-from-source).

## Quick start

```sh
argi init hello
cd hello
argi run
```

Use `argi run --release` for an optimized build, or `argi help` for available commands.

## Learn more

- [Usage guide](docs/usage.md): projects, commands, formatting, and cross-compilation.
- [Language documentation](description/README.md).
- [Application examples](tests/usecase_tests/).
- [Development and compiler tests](CONTRIBUTING.md).

Breaking changes are expected while Argi is experimental.
