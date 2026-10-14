# Contract-scoped dispatch refactor

## Accepted model

Ordinary functions have one identity per module namespace, including all their
compile-time parameter shapes. Contracts own operation identities. `implement`
provides operations and associated elements for a participant tuple; only those
conformances participate in multiple dispatch. Participants come from inputs or
explicit compile-time arguments, never the expected return type. Resolve an
operation identity before ranking conformances. Resolve associated signatures
after selecting the conformance; incompatible calls do not fall back.

Qualified operations use `Contract#(participants).operation(...)`. Unqualified
calls require one applicable identity, including ordinary functions. Composition
retains dependency operation identities. External implementations belong to the
contract module or a nominal participant's module. Equivalent patterns and
incomparable maximal candidates are errors; source/import ordering has no priority.

## Implementation order and removal obligations

1. Continue migration with the remaining bundled operations. Iterator, Iterable,
   ROPointerIterable, RWPointerIterable and OwningIterable now select scoped
   implementations, including concrete/parameterized for lowering and owning
   iterator cleanup. Manual generic iteration and mutable-to-readonly operation
   input adaptation share the same operation resolver. Allocator,
   Deallocator, ErrorTracer, Reader and Writer use selected scoped evidence
   throughout their bundled adapters and callers. BlockReader and BlockWriter
   now share their static/virtual algorithms; StreamTransfer scopes endpoint
   specialization, and BorrowedOrderPolicy scopes owning comparisons. Preserve fallible
   virtual capability inputs, storage acquisition proofs and cleanup. Unary receiver
   safety normalization recognizes the original participant parameter; preserve
   pointer-field dependencies
   and generation facts when migrating each adapter. Continue with the remaining
   bundled core/more operations, including fallible copying. ImplicitlyCopyable and InfalliblyCopyable
   now use explicit Value participants; owning explicit copies remain excluded
   from implicit duplication. ArgumentSource now uses selected scoped operations
   for native arguments and borrowed CLI views; parser/schema consumers retain
   their concrete source type.
   Indexable, IndexableMutable and IndexableValue now use selected Item evidence,
   with dependency identities rather than copied requirements. Resizable selects
   collection/allocation-provider tuples for growth; Removable selects only the
   collection for pop/remove. Named associated restrictions compare against the
   selected evidence and infer ordinary generic leaves. Newly selected evidence
   participates in the resolution/cleanup fixed point.
   OrderPolicy, HashPolicy and BorrowedHashPolicy already use explicit participants
   and scoped implementations. Replace each implicit receiver contract with explicit
   participants and each global operation family with scoped implementations. Remove
   the superseded route as its final consumers move.
   Extend operation input inference to nested associated patterns and reached
   adaptation of by-value bindings. Lexical reach defaults now infer direct
   participants and field paths, including unary virtual receivers. Conformance
   ambiguity diagnostics survive probes.
   Current direct participant inference shares identity selection between
   concrete/generic bodies and compares ordinary generic applicability without
   instantiating its body. Explicit qualified calls remain the escape hatch.
   Remove global overload lookup, legacy function declaration adapters,
   `satisfies` and `Abstract` compatibility once their consumers are migrated.
   No long-term parallel overload mechanism is intended.
2. Add named participant arguments and extend symbolic comparison to remaining
   shapes as needed by these migrations. Current substitution handles type and
   integer parameter leaves, closed types, references, arrays, nominal applications
   with positional/named arguments and repeated-variable equalities. Keep
   arithmetic expressions conservative without inverse inference. Preserve rejection of equivalent and
   incomparable maximal patterns. Equivalent generic patterns and extension ownership are now checked
   even for dormant templates.
3. Validate newly instantiated evidence during resolution so nested operations
   and requirements reach the same fixed point as ordinary calls. Generic aliases now infer their ordinary arguments from selected inputs,
   without selecting by return type.
   Preserve extension ownership and composition operation identities. Give editor
   references and rename actions operation targets distinct from implementation
   bodies; current navigation follows bodies and rename is disabled for them.
4. Init now selects canonical construction from Args/Result evidence, including
   explicit generic and nested calls. Closed anonymous argument defaults use the
   ordinary default lowerer; parameterized shapes preserve scalar/reach defaults.
   Migrate bundled constructors one family at a time, removing all old initializers
   of that family. Mixed Init/legacy families are rejected. Initializer safety and
   projected output dependencies use selected evidence directly. Continue with
   standard Convert and operator contracts. Deinit now selects scoped consuming
   operations for automatic/explicit cleanup, including generic specialization,
   imported owners and ordinary function aliases. Lifecycle wrappers preserve
   alias behavior and forward reached capability inputs. Migrated native owners
   and shape markers no longer use legacy destructor declarations. Generic bundled
   collections, buffered streams and path owners now select Deinit evidence too.
   Owned opaque storage may be emptied only after definite consumption is proved;
   borrowed referents and retention remain separate obligations. Nested collection
   elements and partial owners use recursive lexical cleanup. Continue with
   remaining more-library destructor families and legacy fixture adapters. Replace the
   old constructor/destructor/operator indexes with explicit operation identities,
   preserving resource initialization, cleanup and capability dependencies.
5. Extend unary selected virtual evidence to associated parameters and storage
   domains; the unbound unary case already uses scoped implementations. Support
   joint packages only with explicit representation and safety proofs.
   Remove the remaining compatibility registry adapters and internal Abstract names.

Each step must leave persisted frontend graphs, speculative rollback, dormant
operation validation and safety proofs consistent. Do not disable safety checks
or introduce implicit allocation/copying to simplify the migration. Transitional
source support is allowed only while its callers are being migrated; list its
removal obligation here instead of designing a second permanent subsystem.

## Validation

Add executable and rejection fixtures under the existing contract category.
Keep coverage of module identity conflicts across files, generic-arity conflicts, same-named
operations in separate contracts, missing/duplicate/incompatible implementation
members, alias reuse, associated results, visibility and safety. Verify cold/warm
frontend behavior and emitted direct-call LLVM. Run focused checks with normal
parallel workers, then one full regression after implementation stabilizes.

TODO: preserve contextual fixed-array initialization inside parameterized ordinary
function bodies. A local `[1]UInt8 = (0)` currently makes specialization report an
incorrect generic-input mismatch; concrete bodies accept it. Keep this independent
from virtual participant evidence and improve the body diagnostic before removing
legacy ordinary resolution.

## Execution record

- Ruling: retain one operation identity for readonly indexing; mutable/value
  contracts require Indexable with equal Item evidence rather than repeating
  length/get_ro_ref. This preserves dependency namespaces. If incorrect, callers
  needing an independently specialized readonly implementation must declare a
  different capability explicitly.
- Ruling: Resizable selects Collection and Provider for allocating growth;
  Removable selects Collection alone for pop/remove. Allocation-free operations
  cannot infer a Provider participant. If incorrect, protocol names need revision,
  but ownership and allocation dependencies remain explicit.
- Selected evidence validation joins the ordinary resolution/cleanup fixed point;
  newly selected dependencies are validated in the same pass. Negative spatial
  fixtures exposed previously unvalidated operation tables during this migration.

- Ruling: recognize standard lifecycle identities only from bundled core; a
  same-named user contract cannot redirect compiler construction. A canonical Init
  blocks structural fallback on argument mismatch and rejects legacy initializers
  of the same family. If incorrect, customization requires an explicit protocol
  extension; it never silently changes construction or ownership.
- TODO: extend generic record defaults beyond scalar literals, payload-free choice
  variants and reach directives
  through a caller-aware expression instantiation path. Do not execute effectful
  defaults while materializing types.

- TODO: report missing fields in specialized implementation bodies at their
  source location; UnknownParameterizedField currently escapes as an internal
  semantizing failure when the selected body is invalid.

- Ruling: lifecycle destruction belongs to the selected Deinit operation, not an
  aliased ordinary function. A tracked wrapper carries the same capability
  dependencies as that body; it neither erases them nor adds another dispatch
  registry. If incorrect, the operation representation must change without
  changing the ordinary function's identity or weakening capability checks.
- Whole-receiver destruction supersedes owned field post-values, while effects
  through reference-field dereferences remain visible for conformance checking.
  Consumption requires initialized caller storage. Unknown pointer parameters
  carry separate symbolic consumption identities, preserving shared borrow roots
  and the pointer-slot/pointee distinction. Copies, joins and loop equality retain
  those identities; only whole unknown pointer inputs use that proof. Keep these obligations in summaries and caller proofs.
- Validation: the Init checkpoint passed 1809 programs (11 skipped, no failures)
  and 374 compiler tests (1 skipped). This predates the Deinit changes.

- Review found that loop equality must include symbolic initializedness and alias
  identities. The loop-carried alias fixture reproduced an accepted double
  consumption before that fix. Aggregate envelopes and opaque domain selectors
  are excluded from whole-pointer symbolic consumption.
- Symbolic unknown-input reinitialization remains conservative and cannot revive
  an earlier alias. Extend its outcome/generation precision only with explicit
  guards; concrete caller-place proofs keep their existing behavior.

- Synthetic lifecycle functions retain the FunctionId alignment of the function
  and operator metadata arrays. Comparison specialization fixtures caught a
  missing empty operator entry after a destructor wrapper was appended.

- Validation: the Deinit checkpoint passed 1831 programs (11 skipped, no
  failures or leaks) and 374 compiler tests (1 skipped). Read-only review found
  no further issues after the loop and FunctionId metadata fixes.

- Numeric classification now uses explicit Value participants and implement;
  the 17 legacy numeric conforms and Float default representation are removed.
  Color fields name Float32 explicitly. Generic constraint diagnostics use the
  contract terminology.
- Generic implementation ownership checks concrete nominal leaves and external
  type references as well as nominal applications. A local nominal participant
  with a generic peer is covered by an executable regression; foreign extensions
  remain rejected.

- TODO: fix manual generic error-reason repacking into a wider Error record.
  Constructing `..error(.reason = err.reason)` from a one-variant reason choice
  into a two-variant choice currently produces an LLVM insertvalue layout
  mismatch. Ordinary `!` propagation already remaps reasons and preserves the
  tracer correctly; use it for the upcoming unified array-copy algorithm.

- Validation: numeric classification and nominal ownership passed 1836 programs
  (11 skipped, no failures or leaks) and 374 compiler tests (1 skipped).

- All bundled core/more destructor families now use Deinit, including generic
  collections, path owners, buffered streams and optional Python owners. Generic
  collection cleanup recursively destroys stored owners on success and error
  exits. Explicit cleanup needs no separate allocator: Allocation retains its
  selected deallocation evidence. Legacy allocator/generic call arguments were
  removed from their consumers.
- Consumption permits emptying owned opaque storage only after definite
  destruction is proved. Borrowed referents, unrelated inputs, symbolic domains
  and retention effects remain rejected. Outcome-selected consumption uses the
  selected outcome's definite proof.
- Validation: the bundled destruction run covered 1837 program cases (11 skipped).
  One legacy fixture's unused allocator prevented nested element cleanup; after
  removing that dependency its 93-case worker passed. The other workers passed,
  and 376 compiler tests passed (1 skipped), with no leaks.
- Generic Init argument shapes retain payload-free choice defaults. Matching
  accepts already-equal scalar defaults while retaining range checks. Logger
  construction now uses selected Args/Result evidence and preserves writer loans.
- Logger has explicit Value participants and scoped static/virtual operations;
  FileLogger, StdLogger and NullLogger no longer share a global log overload
  family. Scalar classification also uses explicit participant conformances.
- Numeric post-values may retain place-origin evidence without granting hidden
  storage permissions. Exclude that evidence from the numeric occupancy check,
  retaining it for identity checking and keeping resource effects constrained.
  A reached capability used by array-element destruction is covered together
  with rejection of consuming that capability's owned storage.

- Validation: 230 contract/logging/more cases and 850 ownership,
  polymorphism, collection and loop cases passed, with no failures or leaks.
  All 376 compiler tests passed (1 skipped).

- Fallible array-copy failures now use ordinary propagation instead of manually
  rebuilding Error records. This retains the selected tracer and delegates
  partial-prefix destruction to the lexical array owner. The allocation-failure
  regression checks cleanup order and invokes the returned tracer to verify its
  identity survived propagation.
- The legacy fallible-copy family could not infer associated reasons for a
  custom owning element with a Deinit implementation. The scoped replacement
  below covers this executable case, including a reason distinct from
  out_of_memory, nested arrays and partial-copy cleanup, without retaining its
  overload inference as a second copy mechanism.
- Validation: 165 collection and related ownership program cases passed, with
  no failures or leaks.

- FalliblyCopyable now declares Value and allocator Provider participants, with
  associated reasons selected jointly. String, Path and DynamicArray use scoped
  operations. One array implementation recursively copies elements through that
  selected protocol; infallible elements use a non-allocating adapter whose
  conservative reason choice includes out_of_memory.
- Ownership no longer scans ordinary functions named copy. It checks infallible
  conformance and conservatively queries fallible implementation patterns with a
  known value and unknown provider. Unknown participants can restrict implicit
  copying but cannot grant conformance or select operations. Bound constraints
  are checked; constraints depending on unknown participants remain possible.
- Executable regressions cover ordinary copy names without ownership effects,
  generic fallible copy rejection for plain scalar values, nested array copying,
  and partial cleanup after a user-defined element-copy error. This replaces the
  previously blocked legacy inference case rather than extending its overload
  mechanism.
- Validation: the full program run passed 1844 cases (11 skipped), with one
  outdated String-copy call missing its provider argument. After migrating that
  call, its complete 69-case worker passed. This covers all 1845 positive program
  cases with no leaks. All 376 compiler tests passed (1 skipped). The nested and
  user-error copy regression also executed directly; LLVM 21 assembled its IR.

## Argument-type participant exploration

Construction can keep its allocator generic without making it part of the
constructed owner type. Model the argument record as a participant alongside
the target: `Init#(Target, Args)`. An implementation pattern such as
`(.allocator: $&A, .length: UIntNative)` determines A from a known input field;
Result remains uniquely determined by the complete participant tuple.

The initial exploration used a local Construct contract to exercise ordinary
contract resolution before changing standard Init. Both nominal generic argument records and anonymous records
work. Anonymous record inference and specificity compare ordered field names,
field types, reference mutability and repeated generic bindings. Closed generic
patterns specialize open records; incomparable patterns remain ambiguous.

The standard Init migration below follows these rules:
- Infer Args from supplied arguments while contextualizing literals. Defaults and
  reached capabilities need candidate input shapes, not inverse inference from
  Result. Reject competing shapes by contract specificity, not arbitrary scoring.
- Make the target explicit for constructor syntax; ordinary operation inference
  cannot infer a participant appearing only in Result.
- Preserve defaults as call-completion metadata rather than participant identity.
- Lifecycle evidence retains Target as the first participant while
  accepting the Args participant; preserve rollback and cleanup obligations.
- Migrate existing Init implementations and construction tests together. Do not
  add a second constructor registry or retain a parallel permanent protocol.

This exploration affects semantizing only: record types and runtime operation
calls already have syntax and codegen support. It introduces no erased allocator
representation, implicit allocation, generic associated families or Context.

Validation: all 230 contract program cases passed without leaks; 376 compiler
unit tests passed (1 skipped). The allocator-record executable passed directly,
and LLVM 21 assembled its emitted IR. Its constructor calls the selected
PageAllocator allocate implementation directly.

- Standard Init now uses Target and Args participants; Result remains associated.
  Existing bundled Init declarations and fixtures have migrated, without a unary
  compatibility route. Construction infers generic leaves from the requested
  target and argument fields, including lexical reach defaults, then completes
  literals/defaults and selects by contract specificity rather than call scores.
  Pending explicit and assumed inputs defer selection. Lifecycle evidence keeps
  Target as its first participant for cleanup and output validation.
- String and DynamicArray construction now use provider-generic argument records.
  String's canonical form takes length; reserved empty buffers use the existing
  string_with_capacity factory. The superseded initializer families are removed.
  Executable coverage constructs one owner with two allocator types and with a
  reached allocator; a rejection fixture checks escape from a local provider.
- Validation: all 1853 program cases passed (11 skipped), with no failures or
  leaks; 376 compiler tests passed (1 skipped). The focused migration run passed
  873 programs. LLVM 21 assembled the two-provider constructor IR, which retains
  direct calls to PageAllocator and GeneralPurposeAllocator implementations.

- Nineteen more bundled constructor families now use Init: ArenaDomain,
  GeneralPurposeAllocator, ArenaAllocator, buffered readers/writers, both limited
  reader adapters, OwnedLineReader, RingBuffer, Deque, BitSet and BitSetView,
  both priority queues, and all five map/set owners. Allocating argument records
  keep the concrete provider generic; borrowed adapters retain source loans.
- Ordinary and nested generic construction infer target parameters from Args
  patterns when the type name supplies only its nominal family. Explicit target
  annotations retain their normal contextual role. Result never supplies missing
  generic parameters. Closed and generic patterns participate together; different
  inferred target instances are not ranked merely by equal argument records.
- Map policy fields move from Args into lexical owners before fallible branches.
  A new executable checks exactly-once policy destruction on failed construction
  and successful explicit cleanup. Regression coverage includes inferred target
  construction in concrete/generic bodies and ambiguous/uninferable targets.
- Validation: all 1858 program cases passed (11 skipped), without failures or
  leaks; all 376 compiler tests passed (1 skipped). The focused foundation run
  passed 883 cases (1 skipped), and the owned-policy regression executed directly.
  LLVM 21 assembled its constructor/cleanup IR.

### Scalar equality evidence

Route concrete and parameterized scalar equality through Equal. Extend the private
bundled representation marker to Bool, Char and RawPointer. Lower a selected pure
primitive body only after proving its exact argument projections and output
assignment, sharing that proof with arithmetic. No syntax or codegen schema changes
are required. Validate generic/qualified calls, literals and NaN; preserve tag and
C-boundary comparison lowering. Ordered comparison migration remains separate.

### Ordinary overload inventory after scalar equality

The source inventory groups declarations by their folder module and function name.
It excludes scoped implementation members. This is a migration inventory, not a
semantic claim that every pair has overlapping applicability.

| Module | Names with multiple ordinary declarations |
|---|---:|
| `core/bytes` | 10 |
| `core/errors` | 1 |
| `core/io` | 1 |
| `core/libc` | 1 |
| `core/lists` | 12 |
| `core/maps` | 13 |
| `core/memory` | 2 |
| `core/numbers` | 3 |
| `core/strings` | 7 |
| `core/system` | 6 |
| `core/system/file_system` | 10 |
| `core/testing` | 4 |
| `core/time` | 2 |
| `more/math/linear_algebra` | 5 |
| `more/python` | 9 |
| `more/semver` | 1 |

The four linear-algebra `add` declarations now use Add evidence. Prioritize
the foundational IO formatting/writing and collection view families next. Preserve
static allocator participants and explicit references. Private numeric families
(`integer_limits`, `_float_encoding`, `_float_replace_bits`) should use one generic
function or a scoped representation contract. Renaming unrelated operations is
appropriate when they do not represent one shared protocol. Optional Python APIs
need a separate migration without introducing a mandatory runtime dependency.

Do not reject every duplicate ordinary name until these callers and declarations
have been migrated; the old ordinary overload selector remains pending removal.

Scalar equality validation: 1,899 program cases passed (11 skipped), and 374
internal tests passed (1 skipped), with no failures or leaks. The emitted LLVM
retains ordered float equality and the executable NaN regression passes.

### Linear-algebra addition migration

Replace the four ordinary add families with scoped Add conformances. Fixed
participants share dimensions and element type; dynamic Args retain the static
allocator provider and Result preserves dimension/allocation errors. Update
callers to explicit-reference operator syntax. This affects library declarations
and semantic evidence selection only, with no tokenizer, syntax or codegen changes.
Validate fixed/generic/qualified addition, dimension rejection, empty vectors,
runtime shape failures and refusing providers; remove the former ordinary names.

Validation: all 287 contract and official-library program cases passed, with
no failures or leaks. Selected matrix-add LLVM uses scalar additions and the
executable returns zero. The compiler implementation is unchanged in this step.

### Numeric stream formatting

Replace the two numeric format_into overloads and two numeric write wrappers
with WriteValue(Stream, Value).write_value. Stream and value select evidence
jointly; closed numeric participants share one integer and one float algorithm.
Members reuse the two unique generic helper functions directly, preserving their
identities without forwarding bodies. Two identical participant patterns with
different bounds are deliberately rejected;
do not use constraint-only overloads for conformance specialization. Update numeric print
and fixtures to qualified calls, keeping nonallocating encoders, byte failure
propagation and no implicit flush. Syntax and codegen are unchanged. Validate
all numeric widths, failure paths, custom specialization and virtual writers.
The remaining text/buffer write family and string format_into remain pending.

TODO: Empty participant inference for WriteValue#().write_value reports missing
argument in concrete and parameterized calls. Use explicit Stream/Value participants
for this protocol until the general scoped-operation inference issue is resolved.
The virtual-writer fixture confirms the ordinary generic forwarding path works.

Validation: 400 IO, text, contract, official-library, logging and semver
program cases passed, alongside 35 selected internal tests, with no failures
or leaks. The full Float16 encoding roundtrip passes. Final LLVM calls the reused
helper directly for concrete and virtual writers; the specialization executable
returns zero.

### Unified destination writes

Add associated Result to WriteValue to preserve text Void results, buffer counts
and native socket errors. Replace the three ordinary Writer write overloads and
File/TcpConnection write variants with selected conformances. A unique generic
write(self, value) entry delegates to scoped evidence and requires it explicitly.
Migrate callers, retain partial native progress and saved FFI dependencies, and
validate concrete/virtual streams, native files/networking and specialized outputs.
This is a library migration; syntax and compiler dispatch remain unchanged.

WriteValue.Result permits destination-specific results without return-driven
selection. Native helpers are directly reused as members, preserving function
identity and FFI dependencies. Alias diagnostics preserve a dependency's specific
conformance failure and source-module-backed names across speculative rollback.
The new negative fixture checks that the root protocol is reported.

The unique write entry moves owning Value and Result explicitly. An identity
conformance returning an owned value verifies exactly one destruction through
the selected forwarding call. LLVM preserves the owned result type.

Validation: 508 affected program cases passed (1 skipped), covering IO,
text, contracts, system, official libraries, codecs, logging and semver. The full
internal suite passed 374 tests (1 skipped) during the preceding full run, which
was interrupted before program completion. The affected-category rerun completed
without failures or leaks. Owned-result execution and selected LLVM were checked.

### Fixed array view evidence

Replace the mutable/readonly ordinary view overloads with one ViewOf(Source)
entry. Source includes reference mutability; associated Result preserves the
corresponding view representation. Existing checked array_view algorithms retain
storage provenance. No syntax or codegen changes. Validate generic calls, zero
length arrays, mutable writes and negative borrowed-view escapes. The remaining
array_view/array_view_ro construction families remain pending.

Validation: 490 collection, contract, IO and official-library program cases
passed with no failures or leaks. Generic mutability selection, empty arrays and
local-storage escape rejection pass; emitted LLVM and executable were checked.
