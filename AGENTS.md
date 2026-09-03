# Repository Guidelines

This repository contains a compiler for a new programming language written in Zig.


## Project Structure & Module Organization

- `core/`: Core modules (standard library for the compiler).
- `src/`: Source files for the compiler.
    - The compiler is structured in four phases:
    tokenizing, syntaxing, semantizing and codegen.
- `tests/`: Example `.rg` programs used as tests.
    - Test cases live under `tests/<case_name>/main.rg`.
    - Files in the same test case directory share namespace and are compiled together as one folder-level module.
    - Negative tests should include `X` in their numeric prefix, e.g. `131X_multiple_dispatch_ambiguous`.

- `more/`: Official library modules that are not part of `core/`.

- `description/`: Design documents and architecture notes.

- `references/`: Local reference checkouts.
    - `references/go`
    - `references/zig`
    - `references/odin`


## Usage

- Build compiler: `zig build`
- Run compiler tests: `zig build test`
- Compile a test program: `./zig-out/bin/argi build tests/00_minimal_main`

> It might be necessary to set the following environment variables to make zig work:
> `ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"`
> `ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"`
>
> The current compiler has been updated to run with Zig `0.16.x`. If the local
> Zig version differs significantly, check `build.zig` and stdlib API
> usage before assuming a compiler regression.
>
> LLVM 20 is the supported local codegen baseline. When multiple LLVM versions
> are installed and the unversioned `llvm-config` selects another release, set
> `LLVM_INCLUDE_DIR`, `LLVM_LIB_DIR`, and `LLVM_LIBS` from `llvm-config-20`.


## Guidelines

- To add a new feature:
    1. Checkout the language description and `more/` to understand the
       feature.
    2. Create a `.rg` test that demonstrates the feature in `tests/<case_name>/main.rg`.
       Put positive executable cases under `tests/<case_name>/main.rg`.
    3. Draft a small implementation plan, evaluating whether the change affects
       tokenizing, syntaxing, semantizing or codegen.
    4. Implement the feature in `src/` until it compiles.
    5. Ensure all tests pass and generated LLVM IR makes sense for the feature.
    6. Add the test to `tests/test.zig` where applicable.
    7. Evaluate if the diagnostics need improvement for the new feature and
       enhance them.

- During development, if some error diagnostic is not clear or useful enough
improve it.

- If during development of a feature, you find some tangential improvement that
should be made, or you foresee that some area needs further work, if it is not
worth it to handle it at the moment, mark it as a TODO and focus on the main
feature first.

- Keep CLI help aligned with the tool's current capabilities.

- When validating the compiler locally, prefer:
  `env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build test`

- Current module rules in the compiler:
  - all `.rg` files in a folder share namespace
  - `argi build` compiles a folder module, not a single `.rg` file
  - `#import(...)` must be assigned to a name
  - `./` is current module, `../` is parent, `.../` is project root
  - bare import names resolve under `more/`

- Compiler phase naming is standardized and should stay consistent:
  - use `tokenizing`, `syntaxing`, `semantizing`, and `codegen` for the four compiler phases
  - avoid introducing synonyms such as `parsing`, `analysis`, or `semantic` as the primary names for those phases in new APIs, diagnostics, timing output, or docs
  - umbrella names like `frontend` are fine when referring to the combined pre-codegen pipeline, but phase-specific entrypoints and labels should still use the standardized phase names

- Follow Zig coding style:
    - spaces, snake_case for variables/functions/files, descriptive names.
    - File naming: `snake_case.zig` (e.g., `parser.zig`, `type_checker.zig`).

- Use comments to explain non-obvious code, especially complex algorithms or
design decisions. If you leave comments, ensure they are descriptive and
timeless; not refering to the current change.

- If you want implementation references, inspect `references/go` and
  `references/zig`, and `references/odin` for architecture and algorithmic
  ideas.

- Treat `references/` as inspiration only. Do not copy or mechanically
  translate code, comments, tests, docs, APIs, type layouts, or file structure.
  Re-express ideas in argi's own design and implement them with original code.

- In `core/`, when a `feature.rg` has become a reasonably complete
implementation, remove the corresponding `feature.txt` scratch/design file and
move any still-useful notes into comments in `feature.rg`. If some ideas remain
unfinished, leave them commented there rather than keeping a parallel `.txt`
file around.

- Keep commits small and conceptually focused. Each commit should be one
  coherent unit of change, with any corresponding tests and documentation in
  the same logical commit when appropriate. Do not mix tangential refactors
  into the main task.
- Write clear commit messages in English with an imperative subject that
  describes the change, not the process used to discover it. Avoid vague or
  temporary subjects such as `fix stuff`, `update`, or `wip`. Use the
  repository's natural subject style; do not add Conventional Commit prefixes.

- If you think some important information is missing from this guide, please
add it. If you learn something non-obvious, document it here so future work is
faster.
- Compiler architecture and performance findings should not live only in commit
  messages or temporary notes. When a round of compiler work changes the shape
  of `tokenizing` / `syntaxing` / `semantizing` / `codegen`, or produces a
  useful measured conclusion, document it close to the implementation with
  comments in the relevant compiler source files. Use `description/*.md` for
  language design, not compiler-internal architecture notes.

- Treat `plan/*.md` as active planning documents. If you notice they are
  outdated while doing relevant work, update them so they remain useful as
  development references.
- When a feature or tooling milestone is clearly finished, update the relevant
  checklist in `plan/0.1.md` in the same change if practical. If you choose not
  to update it immediately, leave an explicit TODO in code or docs explaining
  the mismatch so the plan does not silently drift.


## Release workflow

- `main` contains only published, stable releases. Do not use it for normal
  development or merge incomplete work into it.
- `develop` contains development for the next release. Normal work and
  temporary branches start from the appropriate point on `develop` and merge
  back into `develop`.
- Prepare a release on `develop`. When the preparation changes release notes,
  version metadata, plans, or other release artifacts, keep those changes in a
  focused commit named `Prepare release X.Y.Z`.
- Publish by checking out `main` and merging `develop` with an explicit
  no-fast-forward merge whose message is exactly `Release X.Y.Z`:

  ```bash
  git merge --no-ff develop -m "Release X.Y.Z"
  ```

- Create the release tag as an annotated tag named `vX.Y.Z` on that merge
  commit.
- Immediately fast-forward `develop` to the published merge; do not create a
  later `main`-to-`develop` merge commit:

  ```bash
  git switch develop
  git merge --ff-only main
  ```

- Immediately after publication, `main`, `develop`, and `vX.Y.Z` must identify
  the same commit. Subsequent development continues from that common point on
  `develop`.
- Keep temporary branches short-lived. Delete them locally and remotely once
  their work is integrated. Before deleting an old branch, verify that it does
  not contain unique work; preserve and rebase unique work onto the appropriate
  current base when necessary.
