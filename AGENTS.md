# Repository Guidelines

This repository contains a compiler for a new programming language written in Zig.


## Project Structure & Module Organization

- `compiler/`: Zig sources for the compiler.
    - `src/`: Source files for the compiler.
        - The compiler is structured in four phases:
        tokenizing, syntaxing, semantizing and codegen.
    - `tests/`: Example `.rg` programs used as tests.

- `modules/`: Early standard library module drafts.

- `description/`: Design documents and architecture notes.


## Usage

- Build compiler: `cd compiler && zig build`
- Compile a test program: `./zig-out/bin/argi build tests/example_test.rg`


## Guidelines

- To add new feature:
    1. create a `.rg` test that demonstrates the feature in `compiler/tests/`
    2. implement the feature in `compiler/src/` until it compiles.

- Follow Zig coding style:
    - spaces, snake_case for variables/functions/files, descriptive names.
    - File naming: `snake_case.zig` (e.g., `parser.zig`, `type_checker.zig`).

- Commits: focused, descriptive subject in imperative mood (e.g., "add binary literals to lexer").

- If you think some important information is missing from this guide, please add it.

