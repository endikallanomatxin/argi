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
- Run compiler tests: `zig build test -j16 -Dtest-jobs=16`
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
  `env ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-global-cache zig build test -j16 -Dtest-jobs=16`

- Use `-j16 -Dtest-jobs=16` for routine validation, including filtered runs.
  Reduce both limits on constrained machines; retain the serial diagnostic
  exception below for memory-growth investigations.
- For large program-fixture runs, prefer
  `zig build test-programs -Doptimize=ReleaseSafe -j16 -Dtest-jobs=16`, retaining
  a separate Debug `test-internal` run. This optimizes the compiler and test
  runner; fixtures still use their CLI-selected Argi build mode. Finish the
  active suite before switching optimization modes and reinstalling bundles.
- Program tests use one process per worker, automatically choosing the CPU count
  capped at 16. `-Dtest-jobs=N` sets the worker count and `-jN` limits concurrent
  build steps. Shared-state tests finish before fixture workers start; fixtures
  stay on one worker. Per-worker totals and optional active-case progress are
  recorded under `.zig-cache/program-tests/`.

- CLI builds reuse canonical module snapshots under `.argi-cache/frontend/`.
  Use `argi build --no-cache` when comparing against a fresh frontend build;
  `--stats` reports reuse. Global semantizing, safety, and codegen still run.
  Measure in-memory reuse with
  `zig build -Doptimize=ReleaseSafe benchmark-frontend -- <module-directory>`
  (optional iteration count). It compares clean/reused frontend work and edits;
  source collection, codegen, and linking are outside these timings.
  The parallel ModuleSema experiment accepts `--frontend-jobs N` on CLI builds
  (default auto: half the detected logical CPUs, capped at 8). Use 1 when
  an outer build already schedules many compiler processes. Fixture helpers and
  `argi test` select one frontend worker; concurrency tests explicitly override it.
  Pass `[iterations] [frontend-jobs]` to benchmark-frontend to compare
  bounded worker counts. Keep benchmark runs separate from active test suites.

- When investigating compiler memory growth or recursive function-summary
  expansion, run focused tests serially with `-j1 -Dtest-jobs=1` and apply a
  process memory limit where supported. Record the first failing test and peak memory use
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
  - Iterator protocol calls generated for `for` retain the loop's lexical
    reach context and participate in late reached-input completion. Preserve
    both module-visible bindings and specialized `assume` values; an empty
    context can leave call arguments inconsistent with the final signature.
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
  Arithmetic uses Add, Subtract, Multiply, Divide and Remainder with Left,
  Right and Args participants. Custom equality uses Equal with the same tuple;
  Equal returns (.ok: Bool), and != negates one selected operation call.
  Ordering uses CompareRelations#(Left, Right), with explicit operand types and
  four Bool predicates. Its blanket implementation consumes Compare#(Left, Right)
  and ordinary Ordering interpreters; scalar specializations retain direct predicates.
  These contracts have no Args participant or default operations. Unordered maps
  to false for all four predicates; TotalOrder excludes unordered by semantic promise.
  C enum and callback equality selects Equal evidence;
  the compiler supplies only their private empty representation classification.
  Infer participant bindings from Args, including reached generic providers,
  never from Result. Concrete and specialized generic expressions share the
  selected-evidence path; no receiver is implicitly borrowed. Trusted scalar
  conformances lower to representation primitives only after selection, keeping
  constants and contextual literal widths. Hooks are private to bundled core's
  scalar_arithmetic.rg. Minimal semantic tests that omit installed core supply
  explicit arithmetic evidence from test_support.arithmetic_core_source; never
  restore a builtin dispatch fallback for tests. Reject conflicting repeated
  bindings as losing patterns,
  without aborting another applicable conformance. Legacy operator declarations
  are rejected; there is no global operator registry or addressed selector.
  The matrix library's MatrixShape associates dimensions and element types;
  MatrixProduct shares the inner-dimension binding and can specialize Result.
  Nominal Multiply adapters delegate to that protocol. Dynamic multiplication
  stores its static provider in Args; no ordinary multiply overload is retained.
  Canonical construction for migrated types uses `implement Init#(T, Args)`, with
  an Args record participant and a Result of T or Errable containing T. Type calls
  infer Args from target/input patterns, complete defaults and reached capabilities
  and invoke the selected scoped init operation. Selected evidence supplies
  initializer safety and projected output dependencies; never add a second
  constructor registry. Generic type calls can infer their target parameters from
  Args in concrete and specialized bodies; never infer those parameters from Result.
  Closed/generic tuples remain ambiguous when they infer incomparable targets.
  Move owning Args fields into lexical owners before fallible construction steps.
  All bundled core and more constructor families now use Init. Single-use
  capabilities reuse named once functions as their init operations; preserve
  their function identity through lifecycle wrappers and entrypoint analysis.
  Reach defaults describe lexical lookup, not values to type-check before lookup.
  Scaled durations, relative deadlines, precise Unix timestamps and copied paths
  use named factories rather than legacy constructor overloads.
  Explicit conversion uses `Convert#(Source, Target)` through the unique ordinary
  `convert#(.to: Target)(.value = source)` entry. Result is Target or one Errable
  containing it; never infer participants from Result. Prefer the ordinary pipe
  spelling `source | convert#(.to: Target)(_)` at call sites; group compound
  source expressions with scalar brackets. Integer range checking
  belongs to core conformances, with compiler hooks limited to primitive casts
  and representable bounds. Numeric type-call conversions are rejected.
  Reference-to-address conversion grants no reference validity or acquisition.
  Constructor declarations use only Init; `TypeName init(...)` is rejected with
  a migration diagnostic. Construction has no nominal initializer association,
  legacy constructor index or output-based generic inference. Preserve speculative
  rollback of selected evidence and generic side effects. Editor constructor
  navigation uses the selected Init operation and the written type name.
  By-value Args records preserve effects through their reference fields. Follow
  explicit dereference projections to caller referents; changes to copied field
  slots stay local. Summary substitution and concrete calls share that distinction.
  Whole unknown pointers retain their consumption identities inside record fields,
  without assigning those identities to aggregate envelopes or opaque domains.
  Distinct consumed reference fields can alias even when they share one input index.
  Migrated cleanup uses `implement Deinit#(T)` and its consuming self operation.
  All bundled core and more destructor families use this mechanism, including
  generic collections and optional Python owners. Cleanup of allocated owners
  uses the deallocation evidence stored in Allocation, without a separate
  allocator input. Definite whole-owner consumption permits emptying owned
  opaque storage, never borrowed referents or retaining new hidden values.
  Automatic and explicit cleanup select the same evidence. Lifecycle wrappers
  preserve ordinary alias-function behavior and forward optional/reached
  capabilities through tracked calls. They create no second destructor registry.
  Whole-receiver destruction supersedes owned field post-values while retaining
  effects through borrowed references. Unknown pointer referents keep separate
  symbolic consumption identities/state; preserve copies, joins and loop equality
  without changing their shared borrow root or inventing concrete pointee places.
  Symbolic consumption targets only whole unknown pointers, never aggregate
  envelopes or opaque domains. Reject uninitialized/repeated destruction.
  Erased receiver consumption stays unsupported until runtime cleanup identities
  exist. Destructor declarations use only Deinit; `TypeName deinit(...)` is
  rejected with a migration diagnostic. Cleanup has no nominal destructor
  associations, legacy family indexes or ordinary-function fallback. Ordinary
  function names never confer destruction semantics. Selected evidence identifies
  receivers and cleanup obligations, including scalar-only owners. Deinit
  preserves borrowed storage: receiver consumption does not authorize replacing
  external references. Auxiliary cleanup counters should mutate stable record
  fields rather than replace a whole borrowed capability.
  Imported nominal construction selects visible Init evidence. Automatic cleanup
  falls back to the defining module when caller lookup finds no destructor; reached
  arguments retain the caller's context.
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

- Atomic storage uses `core/platforms/shared/atomic.c` and its private header
  through both native runtime adapters. Owning atomic cells retain FFI permission,
  keep native addresses private and provide no safe-reference or acquisition
  receipts. Operations currently use sequential consistency. Cancellation tokens
  borrow their source, and cancellation is cooperative; neither atomics nor
  observers establish permission to transfer Argi values/references across threads.
  Native concurrent probes must join all workers before releasing their cells.

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
  progress; zero write progress is an error. Buffered readers and writers borrow
  caller-provided initialized byte views; their construction neither allocates
  nor takes ownership. Omitting the buffer evaluates its zeroed-array default
  independently in the caller scope. Preserve its temporary storage and lifetime
  just as for an explicit argument; no allocator or I/O-specific fallback is used.
  Empty buffers delegate to the base stream. Reader refills publish bytes only on success.
  Deque iterators retain the deque's shape dependency, including in returned
  borrowed elements.
  Limited copies stop without lookahead; owning complete reads check EOF with
  one extra scratch byte and destroy partial owners on error. Reserve bounded
  capacity before consuming a chunk.

- Local whole-binding replacement evaluates its RHS into a lexical owner, runs the
  selected cleanup of the previous value, and moves the replacement into place.
  Ownership finalization uses cleanup activation to omit destruction for proven
  first initialization. Preserve temporary provenance in value-sequence summaries;
  a sequence result must not skip the bindings that establish its dependencies.
  A block's ret_val can also be its last statement: execute/collect its effects
  once, retaining its value across following cleanup. Statically rooted local
  record fields use the same checked replacement sequence
  and a projected cleanup target; only that field changes generation and cleanup
  activation. Constant local reference aliases retain a proven lexical
  cleanup_target on writes; evaluate the original pointer, and update the target's
  cleanup flags, never the reference slot's. The global verifier checks this proof.
  Reference-only bodies that solely forward an input preserve its lexical identity
  through ordinary/generic calls. Use the selected input binding and completed
  argument order; preserve call execution and safety, never substitute defaults.
  Retargetable/unknown aliases and indexed replacement still require an evaluated
  destination and shared cleanup identity. VM lowering rejects owning writes
  through unresolved aliases and indexed storage until those identities are modeled.
  A reference field's cleanup flag describes its slot, never its referent.
  Bytecode cleanup flags are attached to concrete storage by sorted compiler
  layouts and start false on frame entry. Lifecycle queries can address vacant
  storage without reading its value; following pointers and indices still reads
  initialized operands. Reference copies retain target identity, while value
  copies never copy cleanup obligations. Keep general indirect replacement
  rejected until selected plans and native evidence transport are implemented.
  Native addresses do not identify cleanup obligations: zero-sized siblings
  may share an address. Both backends use `5_codegen/cleanup_layout.zig` for
  field/variant shape; transport evidence by owner/projection identity rather
  than recovering it from a physical pointer. Payloadless variants have no
  child storage or cleanup flag.
  Native flags occupy one contiguous preorder block per owner. A projected
  DropState is a view of its subrange; bulk updates must preserve siblings.
  Cleanup layout counts are cached per retained graph and checked for overflow.
  Both backends allocate flags only for bindings referenced by checked cleanup
  plans; ordinary locals without cleanup obligations need no flag storage.
  Immutable record literals can establish reference-field targets through their
  selected initializers. Preserve the original pointer evaluation and renew only
  the reference used for replacement, never sibling fields or record copies.
  Call post-states distinguish preserved, possible and definite initialization;
  an initialized post-state alone can preserve the entry value. Only definite
  writes reactivate unavailable caller cleanup unconditionally. Conditional
  initialization uses represented result outcomes and must not enable cleanup
  on paths that preserve vacant storage.
  Call reinitialization renews the selected argument reference slot, including
  explicit dereference paths through copied or borrowed records; sibling fields
  and earlier record copies retain their old generations.

- Structural automatic cleanup follows record fields and active choice payloads.
  AutoDeinitField keeps variant projections distinct from record fields; preserve
  that distinction in summary substitution, checker state branches, relocation,
  and codegen. Moving a match payload disables the source choice's cleanup.
  Summary cleanup activation follows moves and discriminants and is cached from
  finalized GlobalSG independently of the effects worklist. Nominal constructors
  with destructors produce cleanup obligations even for scalar-only owners,
  including inside nested payloads; those obligations grant no fresh storage.

- Copy permission comes from contracts, never ordinary functions named `copy`.
  FalliblyCopyable selects Value and allocator Provider jointly. Its associated
  reasons feed the single recursive DynamicArray copy algorithm; ordinary `!`
  propagation preserves the original tracer and lexical owners clean partial
  copies. Infallible elements use a non-allocating fallible-protocol adapter.
  Queries with an unknown provider can conservatively forbid implicit copying,
  but cannot establish conformance or select an operation.

- Owning collection operations move generic input values into lexical owners
  before fallible branches. Extract replaced or discarded structural elements
  into lexical owners as well, so their fields receive recursive cleanup.
  Nominal-only opaque drop hooks on generic input slots do not provide that
  cleanup. Keep unchecked replacement helpers limited to copyable metadata.

- HashMap supports copyable and noncopyable keys and values through one table.
  HashPolicy associates one implicitly copyable Query, projects stored keys into
  it, and hashes/compares that representation for insertion and every query.
  Standard text queries use StringView; callers explicitly project owning strings.
  MapQuery shares Query across membership, lookup, removal and extraction;
  readonly/mutable lookup contracts differ by returned access, never key spelling.
  MapLookup borrows values, MutableMapLookup adds mutable access, and
  MapLookupValue requires MapLookup and implicit copying, matching IndexableValue.
  Hashable feeds canonical bytes to a generic block Hasher independently of
  equality. StandardHashPolicy composes Hashable with borrowed Equal evidence.
  It uses FNV-1a-64 with explicit offset basis and no hidden randomness. Integers
  feed their actual widths; text prefixes bytes with its length. Only standard
  Init supplies a default policy value; custom Init requires its policy, and both
  share one initialization helper. Preserve Errable outcome provenance when
  forwarding helper results, so failure does not retain successful-owner loans.
  Compile-time parameter defaults follow explicit bindings and input inference.
  Partial Init targets retain supplied type/integer parameters; never infer from
  Result or reuse a previously instantiated target. Maps receive allocators through
  ordinary explicit or assumed inputs, without reach allocator defaults.
  Copied lookup and key/value iteration require only the copied element capability.
  Default map iteration borrows both fields; mutable entry iteration never exposes
  mutable keys. Hash tables keep occupied entries separate from slot metadata. Move
  extracted structural entries into lexical owners for recursive field cleanup;
  nominal-only opaque drop hooks do not replace aggregate cleanup. Replace
  grouped backing storage as a whole when growing to update sibling lifetime
  roots together. Keys exposed for lookup and iteration remain readonly.

- HashSet and PriorityQueue each support copyable and noncopyable elements
  through one representation. Set queries use the policy Query; insertion consumes keys.
  Only copied set iteration and queue peek require ImplicitlyCopyable.
  OrderPolicy always borrows comparison operands, including sorting and search.
  Collection allocators come from assume, not reach defaults.

- Hash map iteration never exposes mutable keys. Borrowed entry iterators retain
  a direct table shape anchor in addition to their owner loan; return references
  must preserve that anchor explicitly. Value edits through borrowed references
  preserve iteration, while successful put/remove and table growth invalidate it.
  CodepointView borrows an already-valid StringView without a preliminary scan;
  scalar length is computed on demand. Both it and CodepointIterator retain the
  source's storage dependencies. Arbitrary bytes use checked Utf8Decoder or
  utf8_decode_bytes; decoding neither certifies nor freezes their source.
  Checked decoding cursors advance only on success.
  Test entry wrappers report bounded traces before cleanup, then replace their
  trace handle with the program-lifetime noop tracer while preserving the reason
  used by the C wrapper for failure/skip status.

- Local `Errable` handling (`handle error, value { ... }`) lowers to a match
  inside an explicit `value_sequence`. Its result storage is deferred in the
  enclosing scope, while match payloads and handler locals belong to branches.
  The `handle error { ... }` variant has no result slot and discards the success
  payload through ordinary branch cleanup. Both forms retain the containing
  function and loop control-flow context. `!!!` uses the same recovery lowering
  with an ordinary report_trace call and a bare containing-function return.
  Its optional block runs after reporting and before that return, only on error;
  keep the action's lexical cleanup in concrete and parameterized lowering.
  Control headers require grouping brackets around `!!! { ... }` so the block
  cannot consume the enclosing if/while/for/match body.
  Reporting requires a reachable writer; it neither propagates an Errable
  output nor changes the process status. Program main returns no values or
  status_code: Int32; the checked entry supplies zero for no-result completion.
  Deferred actions handle failures locally: return, `!`, `!!`, and `!!!` cannot
  exit their containing function, and loop transfers cannot target an outer
  loop. Deferred bodies participate in cleanup readiness and finalization so
  their local owners and nested defers are cleaned as well.
  Ownership must traverse value sequences nested in initializers, arguments,
  assignments, conditions, and returns before finalizing cleanup. Codegen must
  not retain binding-map entry pointers across recursive expression emission.
  Bound virtual contract identities include associated type/value arguments;
  safety implementation registries must keep those identities separate.

- Executable builds validate conformance declarations at registration and prove
  safety for reached selected operations after concrete summaries converge.
  Keep operation identities distinct when several contracts alias one function;
  ordinary calls do not select every promise attached to that function.
  Automatic cleanup counts as Deinit use, and reached virtual construction
  proves all operations in its evidence. `argi check` and editor diagnostics
  use exhaustive body proofs, including unused concrete implementations.
  Error-reason inference follows the same execution reachability, retaining
  inferred-signature roots. Exhaustive checks infer every body. Rebuild candidate
  signatures on each global pass; reuse only scratch capacity across passes.
- Contract safety conformance is checked after concrete summaries converge.
  Static selection and virtual table construction share declaration validation
  and implementation proofs. Static conformance metadata belongs to GlobalSG,
  participates in speculative checkpoints, and creates no runtime erasure.
  Find Self receivers in the original requirement rather than guessing from
  concrete input types: another argument can have that same concrete type.
  Content writes in preservation protocols should update fields directly;
  assigning the whole receiver replaces its storage generation.
  Virtual safety summaries are generated from fixed declarations and cached
  independently of the concrete-summary worklist. Implementation lists serve
  runtime reachability and conformance, never dispatch effect inference.
  Receiver validity captures the actual erased referent and its generations,
  not the local slot holding a virtual handle. Whole-receiver virtual calls also
  validate external dependencies in mapped opaque storage; reconstructing fields
  alone does not include hidden contents. Confirmed empty outcomes discharge
  those contents without ending the backing allocation. Concrete summaries
  propagate opaque-content requirements separately from pointer liveness through
  calls and cleanup. Trusted slot reads use backing-owner identities; reading a
  region anchor or releasing allocation metadata does not read stored elements.
  Safety branch states share a per-function root namespace. Fresh resources and
  lexical generations must never collide when independently created branches
  join. Initial identities of the same place can materialize on either branch;
  ended generations cannot be revived by later lexical-slot reuse.
  Returned field addresses through by-value reference records retain explicit
  dereference paths. Instantiate their storage dependencies from argument field
  facts, even when the record envelope has no referenced place.
  Summary place paths distinguish a reference-valued field's slot from its
  pointee with explicit dereference
  projections; writing through the reference must preserve the field's facts.
  Choice-indexed generation effects retain input post-states and domain
  invalidations separately from payload provenance. Infer exit effects after
  cleanup, including loop transfers, and keep an unconditional may-effect union.
  Caller proofs identify one call and one current generation; copies/moves retain
  them, but overwrites, later invalidations and independent pending calls cannot
  revive an older root. Refinement never restores caller snapshots. Output slots
  exposed through references conservatively lose tag-based exit filtering until
  indirect discriminant writes have a branch-local model. Resource consumption
  and hidden-state replacement remain separate checked obligations.
  Unconditional consumes clauses require definite deinitialization of known
  mutable-reference inputs on every return. Resolve actual caller places before
  updating cleanup, including aliases and structural fields; a call can consume
  several owners. End nested owned roots without ending borrowed dependencies.
  Cleanup annotations persist and relocate with both direct and virtual calls.
  Outcome-specific consumption selects caller cleanup flags from the returned
  discriminant even for ignored results and indirect returns. Keep possible
  cleanup in activation summaries; never disable it unconditionally from a
  may-consume effect. Reject whole-input conditional destruction without a
  proven result partition.
  Conditional consumes clauses retain current caller facts behind a call and
  generation guard. Selecting a preserving result confirms initializedness and
  existing owned roots; a consuming result ends them. Never restore snapshots,
  revive an overwritten generation or reuse proofs from independent calls.
  Nested clauses inherit common consumption guarantees. Conformance checks
  every reachable selected exit; unreachable selectors have vacuous guarantees.
  Relocation contracts prove a moved source and an available initialized
  destination with exact whole-place provenance. Materialize destination facts
  before clearing source facts. Ending the source slot generation must retain
  transferred owned roots. Calls disable source cleanup and enable destination
  cleanup, including aliases and fields; destinations do not require a live
  prior value, but occupied or overlapping destinations are rejected.
  Conditional relocation cleanup annotations carry an enable/disable action:
  source and destination flags follow the returned selector even when discarded.
  Cleanup activation retains every potentially initialized destination. A
  conditional initialization joined with an untouched available destination is
  maybe-initialized and must not acquire provenance from the empty input slot.
  Relocation refinement is a paired proof of both current slot generations.
  Materialize destination facts before making both places pending. Selecting a
  moving result clears the source and enables the destination; preservation
  clears the speculative destination and confirms current source facts. Keep
  transferred owned roots alive in both cases, and never restore value snapshots.
  Reject overlapping conditional source inputs before applying any effects.
  Contract outcome relocation inherits enclosing guarantees. Build its virtual
  summary from declarations, including available destinations and conservative
  unselected states; implementation lists only prove conformance. Shared input
  transitions across independent outputs require correlated facts. Alternative
  relocation pairs sharing an input require richer post-value provenance and
  remain unsupported.
  Nested generation guards retain their enclosing payload variant path. Partition
  only paths requested by declarations or forwarded results, preserving a
  conservative effect record elsewhere instead of expanding shared choice types.
  Forwarding proofs trace stable lexical initializers to one call and require
  the output assignment on every returning path. Reassigned, loop-produced or
  reference-exposed intermediate bindings lose provenance. Apply the selected
  call's effects at its original position and retain every intervening effect;
  do not reconstruct or restore caller state at the eventual binding use.
  Projections of multi-output result records retain the selected output index;
  fields inside a single returned value do not select another output. Retain
  unrelated and shared may-effects when refining one returned discriminant.
  Numeric field reads preserve choice shape for those proofs without granting
  ownership or reference validity.
  Exact reference and ownership identity proofs also follow ordered lexical
  initializers in straight-line bodies. Require explicit whole-value moves for
  ownership links and a single output assignment. Keep this proof independent
  of may-dependency summaries; reject calls, writes and unknown control flow.
  Direct forwarding proofs require an output assigned once outside loops and
  whose address has not escaped; rewrites retain unconditional may-effects.
  Conditional from_storage clauses are payload provenance permissions, not
  storage post-states. Persist their sources on outcome declarations, inherit
  common sources into nested payloads and reject inherited exact-identity
  conflicts. Conditional empties guarantees live on OutcomePostStates and
  intersect selected returning exits after cleanup. Caller proofs carry the
  current storage generation and opaque call guard; insertion, replacement or
  a second pending call must defeat an older proof. Emptying discharges current
  hidden dependencies without ending owners or restoring snapshots. Conditional
  retains still requires correlated ownership transitions.
  General safety guards use canonical conjunctions of structural choice selectors.
  Entry-input and output selectors have distinct identities; inspecting a mutable
  input after a call cannot prove its entry tag. Each guard shares a complete
  effect record while the unconditional summary remains conservative. Normalize
  ancestor payload tags, duplicates and contradictions without enumerating a
  product of independent choices. Conditions and effects belong to the immutable
  summary arena. Existing outcome records remain the resource-cleanup compatibility path.
  Distinguish exhaustive inferred return regions from sparse declaration guards;
  sparse promises never establish coverage of all concrete returns. General
  conformance requires a complete approximation under the declared conjunction or a weaker
  proven condition. A stronger condition covers only some promised exits and
  cannot establish the contract. Missing independent singleton evidence cannot
  be assembled into a joint guarantee. Conditional payload permissions and
  authoritative input effects must both survive declaration conversion. Convert
  legacy output contracts only after resolving domains and normalizing concrete
  summaries. Refresh derived outcome guards without replacing independent general
  guards. Unreachable output selectors establish vacuous guarantees, including
  when they occur inside a conjunction. Stable terminal selection bodies can infer
  by-value entry-choice conjunctions for output provenance. Reject unsupported
  statements, result rewrites and nontrivial cleanup from this precision path;
  keep every other effect dimension conservative. Inspect block node order rather
  than numeric node IDs, and validate suffixes in enclosing blocks too. Source
  block ret_val can identify the final statement already visited. Literal choice
  arguments can select proven output approximations during summary substitution;
  do not use a later mutable binding value as evidence for an earlier call.
  Outcome contracts select a named output and variant, not the first result.
  Keep that output index through syntax-free IR, relocation, cached snapshots,
  conformance and summary equality. Common clauses apply to every outcome;
  an empty `on` block does not erase their permissions. General `on` clauses
  select named inputs at call entry and named outputs at return. Nested distinct
  selectors conjoin, while repeating a selector follows its payload. Capture
  entry tags and guarded output dependencies before applying any call effects.
  Returned selector evidence has one call identity; copies preserve it, joins
  intersect it, and overwrites discard it. Reconstruct authoritative fields
  before gathering evidence, and require the full conjunction when narrowing
  payload validity. Never change owned roots, acquisition capabilities or caller
  generations from a payload proof. Exact straight-line forwarding of one call's
  outputs remaps their indices and stable input paths; additional effects lose
  this precision. Keep joint generation/opaque effects conservative. Reject joint
  conditional consumes/relocates until caller cleanup identities are modeled.

- Unconditional opaque contracts distinguish `retains(storage, value)` input
  provenance, `from_storage(output, storage)` hidden output dependencies and
  `empties(storage)` guarantees. They do not prove runtime slot occupancy or
  exact hidden owner identity. Retention takes by-value inputs and grants no
  fresh acquisition or caller-place consumption. Capture opaque output
  provenance before applying empty effects; this retains returned dependencies
  without restoring any caller storage. Reject conditional and erased receiver
  effects until their post-states and cleanup identities are representable.
  Opaque domain owner IDs survive lexical slot cleanup for escape detection;
  these IDs never keep a resource or storage generation alive. When a local
  domain has no summary input path, owning and reference-containing outputs retain its
  possible hidden input provenance. Later extraction must preserve that union.
  Opaque summary paths can select a receiver storage domain after projecting
  the receiver. The domain selector is symbolic and is never a physical Place
  projection. Conformance resolves it to one concrete field path; virtual calls
  resolve it through the handle's existing domain identities. Keep it distinct
  in summary equality, substitution and deduplication. Grouped storage and
  mappings through references require additional transfer identities.

- Moving `for ~ item in collection` loops consume through `MovingIterable`.
  Global semantizing wraps the iterator declaration and loop in one lexical
  block; synthetic iterator owners inherit the source item's captured cleanup
  arguments. Loop transfers clean only scopes inside the current loop boundary,
  retaining the iterator until loop exit. Consuming array iterators keep an
  initialized interval over their private allocation; destroy undelivered
  structural elements through lexical owners before marking storage empty.
  Parameterized loops retain their item binding, mode and body in syntax-free
  IR. Specialization resolves the shared iterator protocol before the body,
  so item types are available to dispatch and the same cleanup rules apply.
  Borrowed loops likewise keep synthetic iterator declarations and computed
  collections in that surrounding block. A declaration in a for-node init
  expression bypasses ordinary block initializedness and lifetime checking;
  never put those declarations into an expression-only init slot.

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

- Function outputs cannot depend on a local storage generation that ends on
  return, including by-value input slots, local owners, and temporaries.
  Check dependencies through fields, choice payloads, virtual receivers, opaque
  storage, allocators, and error tracers. Borrowed input referents and globals
  retain their existing lifetimes; normal owner returns transfer cleanup.
  There are no hidden retained frames, storage promotion, or special pinning /
  owner-plus-reference rules. Large-value destination passing and indirect
  returns remain independent ABI decisions and must not relax lifetime checks.
  `System` borrows resources owned by `__argi_entry`.

- Compiler phase naming is standardized and should stay consistent:
  - use `tokenizing`, `syntaxing`, `semantizing`, and `codegen` for the four compiler phases
  - avoid introducing synonyms such as `parsing`, `analysis`, or `semantic` as the primary names for those phases in new APIs, diagnostics, timing output, or docs
  - umbrella names like `frontend` are fine when referring to the combined pre-codegen pipeline, but phase-specific entrypoints and labels should still use the standardized phase names

- Keep Argi source readable: separate setup, validation, traversal, and result
  construction with blank lines inside longer functions. Keep closely related
  statements together rather than inserting a blank line after every statement.
  Prefer inferred bindings when the initializer establishes the intended type;
  retain explicit numeric widths and types needed for contextual construction.
  Use positional arguments for obvious receivers and compact constructors, and
  named arguments when they clarify roles, limits, or similarly typed values.
  Reuse lexical `assume` for capabilities instead of forwarding the same binding
  repeatedly. Preserve explicit capability selection when switching resources.
  Spell Errable type applications positionally, such as `Errable#(Void, Reasons)`,
  including in return signatures.
  Inline a single-use owner or initialized backing array into a borrowing
  constructor when its lifetime covers the consumer. Keep an explicit owner
  when later checked close or other access makes the resource's role clearer.
  At program boundaries, register checked deferred flushing next to output
  setup; a failing deferred flush replaces a pending return error.
  Retain labels required by built-in dispatch, including `.value` on numeric
  conversions, and when omitting a preceding capability input.
  Keep test fixtures explicit when their syntax is part of the behavior tested.

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

- Character literals contain exactly one Unicode scalar and materialize as the
  bundled core nominal UnicodeScalar type, including generic bodies. Their
  validated numeric payload is not a byte or an implicit CChar conversion.
  C-string interfaces use target-resolved CChar; preserve signedness in literal
  contextualization and error-context checks. No builtin Char type remains.
