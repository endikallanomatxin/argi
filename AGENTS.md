# AGENTS GUIDE

This repository contains a toy compiler written in Zig. Please follow the rules below when contributing.


## Working with the compiler

To add new functionality to the language, write new files in `compiler/tests/` and implement the corresponding compiler features in `compiler/src/`.

To build the compiler inside the `compiler` directory:

```bash
cd compiler
zig build
```

Do **not** run `zig build test` (it is not possible within your environment and it wont work). Instead build once and then compile the tests individually. Example:

```bash
cd compiler
zig build
./zig-out/bin/argi build tests/example_test.rg
```

This avoids issues in restricted environments.


## Directory overview

- `compiler/src` – Zig sources for the compiler.
- `compiler/tests` – example `.rg` programs used in the test suite.
- `modules/` – early standard library modules.
- `description/` – design documents.


## Contribution workflow

- Keep commits focused and descriptive.
- Include a short summary and any relevant test output in your PR body.
- Follow the existing Zig coding style (spaces, snake_case names, etc.).
- If you think some important information is missing from this guide, please add it.
