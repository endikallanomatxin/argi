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

> It might be necessary to set the following environment variables to make zig work:
> `ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"`
> `ZIG_GLOBAL_CACHE_DIR="$HOME/.cache"`


## Guidelines

- To add a new feature:
    1. Checkout the language description and draft-modules to understand the
       feature.
    2. Create a `.rg` test that demonstrates the feature in `compiler/tests/`.
    3. Draft a small implementation plan, evaluating whether the change affects
       tokenizing, syntaxing, semantizing or codegen.
    4. Implement the feature in `compiler/src/` until it compiles.
    5. Ensure all tests pass and generated LLVM IR makes sense for the feature.
    6. Add the test to `compiler/tests/test.zig` where applicable.
    7. Evaluate if the diagnostics need improvement for the new feature and
       enhance them.

- If during development of a feature, you find some tangential improvement that
should be made, or you foresee that some area needs further work, if it is not
worth it to handle it at the moment, mark it as a TODO and focus on the main
feature first.

- Keep CLI help aligned with the tool's current capabilities.

- Follow Zig coding style:
    - spaces, snake_case for variables/functions/files, descriptive names.
    - File naming: `snake_case.zig` (e.g., `parser.zig`, `type_checker.zig`).

- Use comments to explain non-obvious code, especially complex algorithms or
design decisions. If you leave comments, ensure they are descriptive and
timeless; not refering to the current change.

- Commits: focused, descriptive subject in imperative mood (e.g., "add binary
literals to lexer").

- If you think some important information is missing from this guide, please
add it. If you learn something non-obvious, document it here so future work is
faster.


