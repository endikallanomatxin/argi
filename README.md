<p align="center">
  <img src="logo.svg" alt="Argi Logo" width="200"/>
</p>

Argi is an experimental general-purpose programming language that aims to
combine high-level expressiveness and ergonomics with low-level performance and
control.

It draws inspiration from Zig's simplicity and explicitness and Rust's
memory-safety guarantees.

Breaking changes are expected as the language evolves.


## Highlights

- **Memory and resource safety.**

  Deterministic cleanup and compile-time tracking of moves, reference
  lifetimes, and value validity.

  Unlike Rust, Argi deliberately allows mutable and immutable references to
  coexist without exclusive borrowing restrictions. Its safety model focuses on
  temporal memory safety rather than preventing data races.

- **Explicit resource control.**

  Argi uses dependency injection to manage access to resources such as memory
  allocators, I/O streams, and other system capabilities. Functions explicitly
  declare their dependencies, while lexical `assume` declarations allow them to
  be supplied implicitly at call sites, reducing verbosity without sacrificing
  clarity.

- **Contracts and polymorphism.**

  Contracts define operations over one or multiple participating types,
  supporting associated types, generic implementations, specialization, and
  multiple dispatch. Virtual types provide runtime polymorphism when needed.

  Argi has no objects or inheritance.

- **Compile-time programming.**

  Compile-time parameters (`#(...)`), execution (`#run`), and conditional
  compilation (`#if`) allow ordinary Argi code to specialize types, evaluate
  computations, and shape programs at compile time.

- **Explicit nullability and error handling.**

  Nullable (`?T`) and fallible (`!T`) types make missing values and errors
  explicit. Optional diagnostic traces (`!!T`) provide additional context
  without imposing tracing overhead on ordinary fallible operations. On failure,
  `expr!!!` reports the error and returns early from the current function.


## A taste of argi

A simple `Hello, world!`:

```argi
main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stdout
    print("Hello, world!")!!!
}
```

A dynamic collection using an explicitly supplied allocator:

```argi
main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stdout
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_

    numbers ::= DynamicArray#(Int32)()!!!

    numbers | push($&_, 10)!!!
    numbers | push($&_, 20)!!!
    numbers | push($&_, 30)!!!

    total ::= 0
    for number in numbers {
        total = total + number
    }

    print(total)!!!
}
```


## Built-in libraries and tooling

Argi includes two official module libraries:

- `core` provides fundamental functionality: memory management, collections,
  strings, I/O, filesystem access, networking, and other system abstractions.

- `more` extends the language with domain-oriented functionality, including
  linear algebra, optional Python interoperability, and experimental CAD
  modeling.

Argi includes native compilation through LLVM, a persistent REPL, building,
checking, testing, project scaffolding, formatting, and LSP support.

```sh
argi init hello     # Create a project
cd hello
argi run            # Build and run
argi build --release
argi check          # Check all function bodies
argi test
argi format
argi repl
argi lsp            # Start the language server for your editor
```


## Installation

Download a [release package](https://github.com/endikallanomatxin/argi/releases/latest)
for Linux or macOS on x86_64 or ARM64. Extract it and add its `bin` directory to
`PATH`, keeping `bin` and `lib` together. A system C compiler/linker is required;
Zig and a separate LLVM installation are not.

See the [binary installation guide](.github/scripts/binary_installation.md) for
platform requirements and setup. To build from source, including on Windows,
see [CONTRIBUTING.md](CONTRIBUTING.md#building-from-source).

## Documentation

- [Language reference](description/README.md): syntax, types, safety, and contracts.
- [Usage guide](docs/usage.md): projects, commands, REPL, and editor support.
- [Application examples](tests/usecase_tests/).
