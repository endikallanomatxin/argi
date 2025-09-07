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

- To add a new feature:
    1. Create a `.rg` test that demonstrates the feature in `compiler/tests/`.
    2. Draft a small implementation plan, evaluating whether the change affects
       tokenizing, syntaxing, semantizing or codegen.
    3. Implement the feature in `compiler/src/` until it compiles.
    4. Ensure all tests pass and generated LLVM IR makes sense for the feature.
    5. Add the test to `compiler/tests/test.zig` where applicable.
    6. Evaluate if the diagnostics need improvement for the new feature and
       enhance them.

- If during development of a feature, you find some tangential improvement that
should be made, if it is not worth it to handle it at the moment, mark it as a
TODO and focus on the main feature first.

- Keep CLI help aligned with the tool's current capabilities.

- Follow Zig coding style:
    - spaces, snake_case for variables/functions/files, descriptive names.
    - File naming: `snake_case.zig` (e.g., `parser.zig`, `type_checker.zig`).

- Commits: focused, descriptive subject in imperative mood (e.g., "add binary
literals to lexer").

- If you think some important information is missing from this guide, please
add it. If you learn something non-obvious, document it here so future work is
faster.


