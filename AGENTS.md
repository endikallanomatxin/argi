# Repository Guidelines

This repository contains a compiler for a new programming language written in Zig.


## Project Structure & Module Organization

- `core/`: Core modules (standard library for the compiler).
- `src/`: Source files for the compiler.
    - The compiler is structured in four phases:
    tokenizing, syntaxing, semantizing and codegen.
- `tests/`: Example `.rg` programs used as tests.
    - Feature cases live under `tests/feature_tests/<category>/<case_name>/main.rg`.
    - `tests/feature_tests/_support/` contains shared fixture modules; compiler unit tests are registered through `src/internal_tests.zig`.
    - Files in the same test case directory share namespace and are compiled together as one folder-level module.
    - Negative tests should include `X` in their numeric prefix, e.g. `131X_multiple_dispatch_ambiguous`.
    - The feature coverage check scans literal case paths in `tests/test.zig`;
      use complete paths in registration tables rather than concatenated prefixes.

- `more/`: Official library modules that are not part of `core/`.

- `description/`: Language specification and open language-design questions.

- `references/`: Local reference checkouts.
    - `references/go`
    - `references/zig`
    - `references/odin`


## Usage

- Build compiler: `zig build`
- Run compiler tests: `zig build test`
- Compile a test program: `./zig-out/bin/argi build tests/feature_tests/basics/01_minimal_main`

> It might be necessary to set the following environment variables to make zig work:
> `ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"`
> `ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"`
> If Zig still selects a read-only global cache, use
> `zig build --global-cache-dir .zig-global-cache test`.
>
> The current compiler has been updated to run with Zig `0.16.x`. If the local
> Zig version differs significantly, check `build.zig` and stdlib API
> usage before assuming a compiler regression.
>
> LLVM 21 is the supported local codegen baseline, matching Zig `0.16.x`'s
> LLVM generation. When multiple LLVM versions are installed and the unversioned
> `llvm-config` selects another release, set `LLVM_INCLUDE_DIR`, `LLVM_LIB_DIR`,
> and `LLVM_LIBS` from `llvm-config-21`.


## Guidelines

- Write all repository-authored content in English, including documentation,
  comments, TODOs, plans, commit messages, and user-facing text. Preserve other
  languages only when they are required by an example, test fixture, or the
  language feature being documented.

- To add a new feature:
    1. Checkout the language description and `more/` to understand the
       feature.
    2. Create a `.rg` test that demonstrates the feature in `tests/feature_tests/<category>/<case_name>/main.rg`.
       Put positive executable cases under `tests/feature_tests/<category>/<case_name>/main.rg`.
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

- CLI builds reuse canonical module snapshots under `.argi-cache/frontend/`.
  Use `argi build --no-cache` when comparing against a fresh frontend build;
  `--stats` reports reuse. Global semantizing, safety, and codegen still run.
  Measure in-memory reuse with
  `zig build -Doptimize=ReleaseSafe benchmark-frontend -- <module-directory>`
  (optional iteration count). It compares clean/reused frontend work and edits;
  source collection, codegen, and linking are outside these timings.

- When investigating compiler memory growth or recursive function-summary
  expansion, run focused tests serially with `-j1` and apply a process memory
  limit where supported. Record the first failing test and peak memory use
  before widening the run; avoid parallel full-suite runs during diagnosis.
  Use `-Dtest-progress=true` to identify an active case when a run stalls.

- `zig build` installs core under `zig-out/lib/argi/core` and the official
  more library under `zig-out/lib/argi/more`. Rebuild after editing either
  library before manually invoking `zig-out/bin/argi`, so validation uses the
  edited installed bundle. Both directories are cleaned before installation
  to remove stale modules.
  Do not overlap build/test invocations that reinstall these bundles: cleaning
  installed core can temporarily remove runtime headers needed by another
  invocation. Run optimization-mode validation serially after the active suite.

- Current module rules in the compiler:
  - all `.rg` files in a folder share namespace
  - `argi build` compiles a folder module, not a single `.rg` file
  - `import("...")` must be assigned to a name
  - `./` is current module, `../` is parent, `.../` is project root
  - bare import names resolve under `more/`
  - underscore-prefixed declarations and fields are module-private; bundled
    core modules are trusted peers and can access one another's private state.
    Private acquisition/allocation receipts therefore protect against external
    modules, while their invariants remain obligations within bundled core.

- Foreign imports (`CFunction` and `ExternFunction`) have a checked logical
  `.ffi` input of the bundled core `ForeignFunctionInterface` type. Codegen
  excludes that input from the C ABI. Keep capability dependencies in ordinary
  call resolution and safety summaries; C-ABI bodies cannot grow implicit
  capability parameters. Pure bounded byte copies use Argi view operations,
  while direct calls to libc `memcpy` still require `ffi`.
  C record representation and call lowering are separate obligations: field
  layout does not establish a by-value ABI. Aggregate classification must use
  the full signature, including register exhaustion. C scalar aliases and
  narrow-value extension attributes derive from `std.Target`; the compiler
  currently selects its native host target. Check imports and exports against
  native C fixtures when extending either boundary. Numeric record lowering
  also tracks SysV SSE register exhaustion and ARM64 homogeneous floating-point
  aggregates; homogeneous ARM64 input arrays require `alignstack(8)` on Linux
  but not Darwin. Numeric unions merge overlapping member classes; ARM64
  homogeneous unions count the largest alternative rather than summing members.
  Keep those rules shared between imports, exports, and calls. RawPointer leaves
  inside C records, arrays, and unions cross as C addresses; output facts use
  `safety/foreign_result.zig` for both checker and summaries. These facts grant
  neither safe-reference validity nor fresh storage acquisition receipts.
  Uniform foreign pointer arrays keep one marker; arrays of records share
  immutable element templates. Numeric union alternatives need explicit empty
  field facts so projection does not inherit another member's pointer effects.
  CIncomplete declarations keep nominal identities without runtime fields or
  layout. Only RawPointer handles may carry them across C boundaries; never
  synthesize an empty-record layout or construct safe references to them.
  Constructors use `TypeName init#(...)(...)` and return the constructed value
  or an Errable containing it. Their explicit association is a nominal
  declaration ID, persisted in ModuleSG and relocated into GlobalSG. Keep
  constructor lookup indexed by that family, independently of output types;
  speculative specializations must roll back their index entries.
  Destructors use `TypeName deinit#(...)(...)`, receive a mutable reference to
  their associated nominal family, and return no values. Their declaration ID
  and lookup indexes follow the same persistence and rollback rules as init.
  Explicit deinit calls retain ordinary input dispatch; automatic cleanup
  collects receiver names only from the target family's indexed destructors.
  Imported nominal constructors consult public initializers in the type's
  defining module. Automatic cleanup falls back to that module when caller
  lookup finds no destructor; reached arguments retain the caller's context.
  Bundled core is already visible, so it needs no second cleanup lookup.
  CFunctionPointer declarations are nominal types backed by signature FunctionIds,
  not runtime symbols or direct callees. Their logical ffi dependency remains
  separate from the physical C signature. Function-address nodes preserve selected
  callback bodies through global semantizing and LLVM reachability. Selection
  requires visible concrete C bodies, without captures or once semantics; callback
  data addresses require RawPointer until foreign lifetime contracts are defined.
  Indirect function_call nodes keep the prototype in callee and the runtime address
  in callee_value. Every call traversal must visit that value before its arguments,
  including checker and summary domains. Codegen shares direct C call lowering,
  applies ABI attributes at the call site, and guards null addresses; prototypes
  must not create LLVM symbols. Generic callback invocation remains pending.

- Optional CPython embedding lives entirely in `more/python`; ordinary builds
  must not require Python headers or libraries. Consumers explicitly compile
  `runtime.c` and link the matching CPython embedding library, or use the optional
  `more/python/build.py` preparation helper. Object owners
  borrow their interpreter and carry private raw handles, never safe references
  to Python buffers. Executable Python fixtures require absolute
  `ARGI_PYTHON_RUNTIME_OBJECT` and `ARGI_PYTHON_LIBRARY` paths; without them those
  fixtures skip, while negative ownership tests still run. The standalone
  `tests/python_native.c` probe checks the native boundary with matching headers.
  Python numeric transfers copy into Python-owned storage or initialized Argi
  views; buffer validation must precede all destination writes, and every acquired
  Py_buffer must be released. Exception snapshots own native text independently
  of interpreter lifetime. Do not reintroduce hidden Python/core dependencies.
  Optional NumPy wrapper execution additionally requires `ARGI_PYTHON_NUMPY=1`;
  its negative ownership fixtures need no NumPy dependency.

- Blocking networking uses `core/platforms/shared/network.c` and its private
  `network.h` ABI header, included by the selected POSIX/Windows runtime adapter;
  Windows links `ws2_32` as well as `shell32`. Keep the shared source and header
  in installed core bundles. Resolution and
  socket owners borrow `Network`, which retains its FFI dependency. Address
  values copy native bytes; no native handle grants safe-reference validity or
  storage acquisition receipts. UDP truncation is an error even when a prefix
  was written.

- Filesystem extensions use `core/platforms/shared/filesystem.c` and its private
  `filesystem.h` ABI header through the same selected runtime adapters. Directory
  and temporary-directory owners borrow `FileSystem`; their native handles grant
  no safe-reference validity. Copy directory names before advancing enumeration.
  Temporary directory cleanup removes only an empty directory; explicit close
  retains the handle on failure so callers can remove children and retry.
  File seek and truncate preserve the owning file's FFI dependency.

- Block stream operations use initialized byte views and readonly write sources.
  Validate complete ranges before binary writes, and advance borrowed byte cursor
  positions only on success. Exact reads and complete writes accept partial native
  progress; zero write progress is an error. Buffered readers initialize their
  allocation before exposing a native refill view. Deque iterators retain its
  shape dependency, including in returned borrowed elements.
  Limited copies stop without lookahead; owning complete reads check EOF with
  one extra scratch byte and destroy partial owners on error. Reserve bounded
  capacity before consuming a chunk.

- Owning hash tables keep occupied entries separate from slot metadata. Move
  extracted structural entries into lexical owners for recursive field cleanup;
  nominal-only opaque drop hooks do not replace aggregate cleanup. Replace
  grouped backing storage as a whole when growing to update sibling lifetime
  roots together. Keys exposed for lookup and iteration remain readonly.

- Hash map iteration never exposes mutable keys. Borrowed entry iterators retain
  a direct table shape anchor in addition to their owner loan; return references
  must preserve that anchor explicitly. Value edits through borrowed references
  preserve iteration, while successful put/remove and table growth invalidate it.
  UTF-8 views validate borrowed bytes without freezing them; callers must preserve
  the validated contents. Checked decoding cursors advance only on success.
  Test entry wrappers report bounded traces before cleanup, then replace their
  trace handle with the program-lifetime noop tracer while preserving the reason
  used by the C wrapper for failure/skip status.

- Local `Errable` handling (`handle value, error { ... }`) lowers to a match
  inside an explicit `value_sequence`. Its result storage is deferred in the
  enclosing scope, while match payloads and handler locals belong to branches.
  Ownership must traverse value sequences nested in initializers, arguments,
  assignments, conditions, and returns before finalizing cleanup. Codegen must
  not retain binding-map entry pointers across recursive expression emission.
  Bound virtual abstract identities include associated type/value arguments;
  safety implementation registries must keep those identities separate.

- Moving `for ~ item in collection` loops consume through `OwningIterable`.
  Global semantizing wraps the iterator declaration and loop in one lexical
  block; synthetic iterator owners inherit the source item's captured cleanup
  arguments. Loop transfers clean only scopes inside the current loop boundary,
  retaining the iterator until loop exit. Consuming array iterators keep an
  initialized interval over their private allocation; destroy undelivered
  structural elements through lexical owners before marking storage empty.

- Pipes preserve one evaluation of computed operands and retain lvalue storage.
  Concrete and parameterized body lowering both reserve private deferred
  bindings in the enclosing lexical scope. Compiler-generated `value_sequence`
  blocks have an explicit result and do not give source blocks implicit returns.
  Traverse their ordered effects in reachability, cleanup, capability and storage
  summaries; return the result's lifetime facts in Safety. Persistent frontend
  snapshots include these nodes, so changes require a codec version bump.

- Compilation target identity lives in `src/1_base/target.zig` and is carried
  by ModuleSG and GlobalSG. Resolve C aliases, layouts, safety checks, and C ABI
  classification from that identity rather than the compiler host. Persistent
  module fingerprints include the target; bump the wire version when its stored
  representation changes. Cross-target object emission initializes LLVM target
  backends and uses the selected target data layout before IR optimization.
  `--cc`, repeatable `--cc-arg`, and `--c-sysroot` configure C linking;
  `--sysroot` remains the Argi installation prefix. Library queries use the
  same driver arguments as final linking. Cross drivers must report a matching
  `-dumpmachine` identity. Linux x86_64 CI executes ARM64 fixtures with QEMU;
  local cross execution uses `ARGI_CROSS_CC`, `ARGI_CROSS_RUNNER`, and
  `ARGI_CROSS_RUNTIME_ROOT`.

- Native Windows development uses Zig 0.16, the official LLVM 21 development
  archive's C API DLL/import library, and MSYS2 UCRT64 GCC for generated programs.
  The standalone LLVM installer does not provide the complete C headers. Set
  `LLVM_INCLUDE_DIR`, `LLVM_LIB_DIR`, and `LLVM_LIBS=LLVM-C.lib`; put `LLVM-C.dll`
  on PATH or next to `argi.exe`. LLVM target triples come from Argi's target
  identity, including the CRT ABI, rather than the LLVM DLL's build host.
  Bundled core selects its POSIX or Windows adapters from that same target.
  Windows page reservations keep private release metadata outside the exposed
  range; never implement their cleanup with partial `VirtualFree` operations.
  Aligned CRT acquisitions must use `aligned_free`, not ordinary `free`.

- CLI linking bundles `core/platforms/posix/processes.c` for POSIX targets and
  `core/platforms/windows/runtime.c` for Windows using the selected C driver
  and target flags. Process adapters share temporary argument storage through
  `core/platforms/shared/process_arguments.h`; keep these headers in installed
  core distributions. Process and pipe addresses are private native handles,
  not safe references or allocation receipts. The owning process closes its
  endpoints and terminates/reaps a remaining direct child during cleanup.

- Target `#if` selection is shared by import discovery and frontend tokenizing
  through `src/1_base/target_selection.zig`. It blanks discarded bytes while
  preserving original offsets and line endings. Keep source buffers intact
  for diagnostics, cache fingerprints, and editor positions. Private platform
  adapters select their own declarations; do not filter source by folder names.
  Target predicates use ModuleSG's target, including during cross compilation.
  Bundled primitive requirements may be target-specific, but selected trusted
  declarations must still satisfy their origin, canonical path, and signature.

- Returned references to bounded local storage use caller-owned frames in
  GlobalSG. `global/storage_promotion.zig` runs after ownership cleanup
  resolution, using provisional safety summaries to distinguish borrowed
  values from borrowed slots; final summaries include retained storage roots.
  Codegen passes frames through a hidden Argi ABI parameter without changing
  dispatch inputs or outputs.
  Retention includes backing storage and delayed-cleanup dependencies.
  Pointer-bearing locals reserve lexical cleanup positions even without a
  source destructor, so receiving values precede their frames in cleanup.
  Caller-storage fresh effects preserve their temporal tag across summary
  rebasing and grant no allocation receipts. Reject unsupported recursive,
  repeated, or virtual retention rather than silently allocating on the heap.
  These cold GlobalSG tables do not enter persistent ModuleSG snapshots.

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
  Keep every line of a commit message at 72 characters or fewer.

- If you think some important information is missing from this guide, please
add it. If you learn something non-obvious, document it here so future work is
faster.
- Compiler architecture findings should not live only in commit messages or
  temporary notes. When compiler work changes the shape of `tokenizing` /
  `syntaxing` / `semantizing` / `codegen`, document the design close to the
  implementation with comments in the relevant compiler source files. Keep
  measured performance results out of source comments; summarize them in the
  relevant commit body as before/after deltas measured in the same environment,
  including enough context to interpret the comparison. Avoid standalone
  absolute timings that primarily describe the measurement device.
  Use `description/*.md` for language design, not compiler-internal architecture
  notes.

- Treat `description/` as the specification of the intended language, not a
  snapshot of the current compiler. Write accepted language design as normal
  documentation, even when it is not implemented yet.
- Use `[!IMPLEMENTATION]` only to note gaps between that specification and the
  current implementation. Use `[!QUESTION]` for unresolved design decisions
  and `[!IDEA]` for exploratory possibilities that are not yet part of the
  language design.
- Keep implementation scheduling, milestones, and work tracking in `plan/`;
  do not duplicate the language specification there.

- Keep release scheduling and development order in `plan/<version>.md`.
  Topic-specific planning notes should describe the mental model, architecture,
  technical dependencies, and remaining work without assigning releases or
  duplicating the release roadmap.

- Treat `plan/*.md` as active planning documents. If you notice they are
  outdated while doing relevant work, update them so they remain useful as
  development references.
- Before merging completed work, remove its finished tasks from active release
  plans and update the remaining development order. Delete dedicated planning
  notes once they have no pending work; do not keep completion reports in
  `plan/`. Move useful lasting knowledge into the appropriate documentation or
  source comments before deleting a note. Include this cleanup in the feature
  branch before merging it into `develop`.


## Release workflow

- `main` contains only published, stable releases. Do not use it for normal
  development or merge incomplete work into it.
- `develop` contains development for the next release. Normal work and
  temporary branches start from the appropriate point on `develop` and merge
  back into `develop`.
- Prepare a release on `develop`. When the preparation changes release notes,
  version metadata, plans, or other release artifacts, keep those changes in a
  focused commit named `Prepare release X.Y.Z`.
- Create the release candidate by checking out `main` and merging `develop`
  with an explicit
  no-fast-forward merge whose message is exactly `Release X.Y.Z`:

  ```bash
  git merge --no-ff develop -m "Release X.Y.Z"
  ```

- Immediately fast-forward `develop` to the release merge; do not create a
  later `main`-to-`develop` merge commit:

  ```bash
  git switch develop
  git merge --ff-only main
  ```

- Push `main` and `develop` together. `.github/workflows/release.yml` validates
  the exact merge commit on Linux x86_64/ARM64 and macOS Intel/Apple Silicon,
  builds relocatable distributions, and exercises the extracted packages.
  Only after every job succeeds does it create the annotated `vX.Y.Z` tag and
  publish the GitHub release with binary archives and `SHA256SUMS`.
- Do not create tags or publish releases manually. Release notes come from
  `releases/X.Y.Z.md`; the workflow does not generate a changelog. To retry
  a failed release, run `gh workflow run release.yml --ref main`. Investigate
  failures before changing the release candidate; published versions must not
  be overwritten without an explicit request.
- Binary packages include non-system runtime dependencies and their license
  notices. Build with a baseline CPU target, preserve the installed core
  layout, and validate relocation. Consumers still need a system C linker.
- Immediately after publication, `main`, `develop`, and `vX.Y.Z` must identify
  the same commit. Subsequent development continues from that common point on
  `develop`.
- Keep temporary branches short-lived. Delete them locally and remotely once
  their work is integrated. Before deleting an old branch, verify that it does
  not contain unique work; preserve and rebase unique work onto the appropriate
  current base when necessary.
