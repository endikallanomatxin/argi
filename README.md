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
- Side-effects are always explicit.
- No objects or inheritance.
- Polymorphism through:
    - Multiple dispatch
    - Generics
    - Abstract types (rust's traits style)
    - Virtual types (dynamic dispatch)
- Errable and Nullable types.
- Big core library.
- Great tooling (official formatter, lsp...).


Biggest, most important TODO: Define memory management further.
(all description files starting with 3)
There are some ideas, but it is still on the air.


## Compiler usage

Build the compiler:

```sh
cd compiler
zig build
```

If Zig needs writable caches, run commands with:

```sh
ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"
```

Compile a program:

```sh
./zig-out/bin/argi build tests/00_minimal_main/main.rg
```

Start the language server:

```sh
./zig-out/bin/argi lsp
```

Available build diagnostics flags:

```text
--on-build-error-show-cascade
--on-build-error-show-syntax-tree
--on-build-error-show-semantic-graph
--on-build-error-show-token-list
```
