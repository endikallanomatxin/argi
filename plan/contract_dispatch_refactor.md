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

### Current ordinary overload inventory

The source inventory groups declarations by their folder module and function name.
It excludes scoped implementation members. This is a migration inventory, not a
semantic claim that every pair has overlapping applicability.

| Module | Names with multiple ordinary declarations |
|---|---:|
| `core/libc` | 0 |
| `core/lists` | 0 |
| `core/maps` | 0 |
| `core/memory` | 0 |
| `core/system` | 0 |
| `core/system/file_system` | 0 |
| `more/math/linear_algebra` | 0 |
| `more/semver` | 0 |

All bundled core and more consumers now use unique ordinary identities or scoped
contract operations. No repeated ordinary declaration names remain in the source
inventory. File opening uses Init with Args; allocation and ownership protocols
retain selected evidence. Legacy fixture overloads and source adapters still need
migration before global ordinary ranking can be removed.

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

### Collection views and single-element factories

Move DynamicArray collection views to ViewOf, retaining shape dependency and
backing allocation provenance in the unchanged private algorithms. Fixed-array
algorithms are also private; all collection callers use the unique view entry.
Empty readonly views and single-element views use uniquely named factories.
Remove ordinary array_view/array_view_ro overload families rather than retain
compatibility wrappers. Validate structural invalidation, empty independence,
mutability and element liveness with the existing spatial fixtures.

Validation: 683 affected program cases passed (1 skipped), plus 35
selected internal tests, without failures or leaks. Spatial invalidation diagnostics
remain intact across growth, insertion, removal, pop and release. Generic dynamic
reference selection and independent empty views also passed direct execution and
LLVM inspection. Callers with local view bindings use borrowed_view or qualified
ViewOf operations to preserve ordinary lexical name resolution.

### Closing ordinary numeric families

IntegerBounds selects limit operations by the value participant; one unique
integer_limits function preserves the public two-output API. Private IEEE
encoding/replacement families share _FloatRepresentation and retain their
existing bit algorithms behind two unique generic entries. No compiler hooks or
return-based selection are introduced. Validate checked arithmetic, classification,
rounding and float text roundtrips before continuing ordinary-family removal.

Unify terminal print into one generic function that delegates rendering to
WriteValue and appends its terminator only on success. Remove its four ordinary
overloads. Archive the explicitly unfinished numeric design sketches as text,
so their rejected operators/Self/satisfies syntax is not shipped as executable
Argi modules. This does not remove the compiler compatibility adapters yet.

StringFormatting selects Value and allocator Provider jointly, reusing unique
private algorithms as members. Ordinary format and format_into now have unique
generic identities. Preserve exact allocation counts, atomic growth failures and
cleanup of temporary encodings. Decimal digit extraction is one generic entry.

ByteCursor scopes position/remaining/skip for reader and writer cursors, with
unique ordinary entries. Indexed endian operations use explicit *_at names,
separate from advancing cursor operations; find_byte is distinct from pattern
search. Preserve range validation before writes and advance only on success.
This removes all ten ordinary overload families in core/bytes.

ContiguousView scopes base-pointer and subrange operations for mutable and
readonly views. Pointer is associated, keeping the stored access mode explicit.
Unique data/slice entries retain checked bounds and storage dependencies; no
conversion to a common writable representation is introduced. Explicit redundant
element arguments at old call sites are removed in favor of participant inference.

CollectionLength and CollectionCapacity replace repeated ordinary queries in
lists/maps. Scoped members directly reuse their unique private helpers. Preserve
readonly receivers, generic policy bounds and exact count output names. Runtime
representation intrinsics for native arrays/views remain separate from nominal
collection algorithms. Other module query identities remain pending migration.

TextViewOf and TextBytes replace strings' projection/byte-read overloads,
preserving borrowed outputs and trailing-NUL behavior of owned strings. The
allocating StringView-to-C-string factory is explicitly named copy_c_string,
distinct from borrowing an existing terminated string via as_c_string.

ReadLimit unifies limited reader queries. TimeCompare and NanosecondCount scope
time queries, retaining duration/timestamp numeric result widths. Bounded memcpy
uses one generic algorithm for mutable/readonly source views. Validate temporal
anchors and native byte operations; no implicit borrow or allocation is added.

### Completion audit after the current ordinary-family batch

The inventory has 52 remaining repeated names (initially 84). Numbers, bytes,
strings, IO and time now have unique ordinary identities within their folder
modules. This is a declaration inventory, not proof that cross-module visible
identities resolve without the old candidate selector. Global ordinary selection
is still present, and legacy syntax/implicit Self fixture consumers still exist.
Do not claim the three completion gates are closed or remove those paths before
their remaining callers have migrated. Next batches are lists/maps, native system
operations, official math and optional Python; testing protocols also remain.

Current batch validation: full suite passed 1909 program cases (11
skipped) and 374 internal tests (1 skipped), with no failures or leaks. Selected
entry LLVM and the custom collection/numeric executable were checked. The ordinary
selector and legacy contract adapters are still pending removal; this batch closes
32 declaration families, not the overall three requested completion gates.

### Optional Python ordinary-family migration

Private scalar/view contracts select numeric transfer metadata, replacing 22
numeric_buffer, 22 numeric_array and 11 copy_numeric declarations with unique
generic algorithms. PythonValue supplies selected conversion evidence behind
one to_object entry. Retain interpreter loans, native buffer validation/release
and independent output storage; ordinary builds keep Python optional.

Python integer, clone, keyword and call families now use private operation
contracts and unique ordinary entries. Clone's associated Result preserves
infallible exception snapshots and fallible Object duplication. Call argument
representations specialize one invocation identity, preserving the canonical
empty-array default. Generic defaults may bind a direct unknown type parameter
from a typed value or a unique local zero-input concrete factory signature,
without executing the factory, using expected outputs, or consulting cached
generic instances. Default materialization has no body-local function context.
The regression fixture checks exact runtime evaluation counts and rejects cached
generic-default inference. Broader default expression inference stays deferred.

All nine optional Python overload families are removed. The remaining inventory
contains 43 repeated names; global ordinary selection and legacy contracts remain
required removal work after those consumers migrate.

Optional Python batch validation: 20 Python/default-inference program cases
passed (0 skipped) with the matching CPython 3.12 native adapter and NumPy
enabled. The full internal suite passed 374 tests (1 skipped); contract/official
library regressions passed separately. All runs had no failures or leaks. The
normal compiler build still has no Python header/library requirement.

### Assertion-family migration

TestEquality selects specialized diagnostics while a generic conformance preserves
ordinary equality assertions. Numeric diagnostic rendering uses closed scalar
conformances and unique integer/float helpers. Text assertion entries are unique;
the explicit raw-C-string failure helper has a distinct name. Preserve exact
failure text, tracer context, success allocation behavior and partial cleanup.

StringMapKey normalizes borrowed key representations through one operation.
StringHashMap has/delete retain one generic facade per action, delegating to
their original private view-key algorithms; duplicate Char/String wrappers are
removed for those exclusive actions. get/put still share the maps namespace with
other families and require a coordinated merge before becoming unique.

Assertion and string-key queries need no ordinary ranking within their completed
families. Generic HashMap get/put are still separate ordinary consumers; the
compiler's existing duplicate-name check prevents switching those partial map
facades to unique identities before their coordinated migration.

Assertion/key batch validation: 474 collection, testing and contract program
cases and 35 internal tests passed, without failures or leaks. The remaining
inventory has 36 repeated names. The ordinary selector and legacy
contract adapters remain open completion gates; this batch does not remove them.

BitSetAccess selects read/write/population for borrowed and owning bitsets.
contains_bit and set_bit distinguish bit positions from value/key collection
operations; count_set has one generic identity. Keep bounded writes atomic,
default true semantics, zero-size behavior and backing lifetime dependencies.

Owning DynamicArray replacement uses the unique replace action, distinct from
copyable view set. It retains moving the incoming value into a lexical owner
before range checks, recursively destroys displaced elements and preserves
shape invalidation. This removes the final ordinary set overload family in lists.

Collection action validation passed all registered collection cases. The unused
allocator-taking trusted_opaque_drop declaration and its primitive approval
signature are removed; cleanup uses the selected Deinit evidence. The declaration
inventory now has 32 repeated names. Ordinary ranking and legacy contract
adapters remain pending the remaining consumer migration.

The mutable/readonly fwrite_from family uses one byte-buffer algorithm, with
private selected evidence preserving the readonly C input. SocketAddress and
SocketTimeout remove the networking local_address/set_timeout families while
keeping their native implementations and safety dependencies. The repeated-name
inventory is now 29; no global-selector or legacy-contract removal is claimed.

Collection/byte-buffer/socket batch validation: all registered collection cases
passed before the byte-buffer/socket migration; the subsequent full system group
passed 102 cases (1 skipped), with no failures or leaks. The full internal suite
passed 374 tests (1 skipped). Both mutable and readonly file writes and TCP/UDP
endpoint and timeout cases exercised selected evidence.

### Resource lifecycle query migration

Replace ordinary close/is_open families with Closeable and OpenState. A single
ordinary close entry preserves associated Result for socket, stream and temporary
directory errors. Open state consistently returns ok: Bool. Implementations reuse
the native algorithms, retaining handle invalidation, caller capability lookup,
closed-resource cleanup and retryable temporary-directory failures. No new lexer,
parser or codegen mechanism is needed; selected evidence carries existing effects.

Resource-state regression uses generic close forwarding with both Void and Errable
results, explicit open-state queries and retryable failures. The native temporary
directory fixture now keeps a child across a failed close, removes it and retries.
The full system group passed 102 cases (1 skipped), with no failures or leaks.
The full internal suite passed 374 tests (1 skipped). The generic regression
compiled and executed successfully; emitted LLVM directly calls its selected
concrete operations for each associated result. The declaration inventory has
26 repeated names; removal of global ordinary ranking and legacy contracts remains
pending migration of their remaining consumers, not complete in this batch.

The registered resource-state regression and the updated native temporary-directory
retry case both passed through the program runner, without failures or leaks.

### Semver operation reuse

Remove semver-local format and format_into entries and its separate as_view
identity. VersionView supplies TextViewOf, StringFormatting with a static allocator
Provider, and WriteValue forwarding the destination's selected string result.
Callers use the shared ordinary format/format_into/as_view/write entries. Preserve
version text loans, allocation counts, no-flush behavior and write/flush errors.
This affects library evidence and callers, with no new compiler mechanism.

Semver migration exposed missing reference transparency in conformance ownership.
Concrete and dormant generic conformance checks now follow readonly/mutable
reference layers to a nominal participant owner. Lifecycle nominal-owner lookup
is unchanged; structural fields and generic arguments do not grant ownership.
Regressions accept concrete/mutable/generic references to local nominal types and
reject concrete/dormant references to foreign types. The semver writer fixture
also checks a custom StringView destination returning a count without Writer.
The declaration inventory is now 25 repeated names.

Semver/reference-ownership validation: all nine focused semver and ownership
program cases passed, including both foreign rejection paths and the counting
destination. The subsequent complete contract group passed 296 cases without
skips, failures or leaks. The full internal suite passed 374 tests (1 skipped).
Global ordinary ranking and legacy contract compatibility remain pending after
these consumer migrations; the three requested completion gates are not complete.

### Queue operation migration

Replace the three ordinary push/pop families with Queue and QueueInsertion
operation identities. Queue associates Item and its removal Result; bounded rings
retain Errable while priority heaps retain optional outputs. QueueInsertion
selects the collection and a static allocation Provider jointly, preserving full
and allocation errors. The provider-independent Item projection supplies literal
context. Reuse existing owning algorithms and scoped backing-array evidence.

Capacity reservation and dynamic-array growth retain their static Provider through
the selected Allocator operation. Remove the unused dynamic_array_grow wrapper
and privatize the actual growth helper. Keep bounds checked before allocation,
lexical input cleanup, ownership relocation and backing-shape invalidation. This
batch changes library conformances and callers, without new compiler phases.

Initial queue validation passed all 14 ring/heap and ownership cases. A generic
queue regression exercises associated removal results, narrow literal context,
reached providers, bounded rejection and heap growth. The declaration inventory
has 23 repeated names; global ordinary selection and legacy contract compatibility
remain pending migration of those consumers.

Broad validation exposed source-spelling-sensitive nominal inference in ordinary
functions and operation aliases: positional nominal participants could not match
named alias inputs. Use declaration-order matching with shared generic argument
lookup across function inference and conformance comparison. Remove duplicate
nominal metadata lookup and argument matcher helpers from the contract resolver.
Queue UInt8/default-provider and copied-array growth regressions now pass. Add
ordinary-function coverage for positional/reordered named type and constant args.

Canonicalize nominal type argument identity as well as inference, validating names
and kinds before instance reuse. Rewrites of pre-existing type argument ranges
participate in graph checkpoints, restoring the old range before speculative pools
shrink. A nested-checkpoint regression checks both restoration levels and pool
lengths. This avoids dangling argument references after losing candidate probes.

The full suite passed 1,918 program cases (11 optional skips), with no failures
or leaks, plus 374 internal tests (1 skipped), before the final checkpoint journal
and cached-instance fast-path adjustment. The nested-checkpoint journal regression
then passed in the complete internal suite: 375 passed, 1 skipped. Final validation
covers contracts, collections, generic cases and optional Python/NumPy using the
matching native adapter. Canonical argument rewrites are released with construction
metadata after GlobalSema, and materialized instances retain their fast reuse path.

Final queue/canonicalization validation passed 509 program cases and 32 selected
internal tests with Python and NumPy enabled, without skips, failures or leaks.
Both new executable regressions passed; LLVM preserves narrow UInt8 results,
declaration-order nominal identity and direct PageAllocator growth calls. No
ordinary push/pop declaration remains in core/lists. The global ordinary selector
and legacy contract adapters remain required removals after the 23 remaining
ordinary families and legacy fixtures migrate.


### File opening migration

Replace the twelve FileSystem open_read/open_write/open_append factories with
four Init#(File, Args) conformances. Args carries the path, FileSystem and explicit
mode (read by default). Char, String and Path references borrow existing terminated
text without a provider. StringView carries a static Allocator provider in Args,
including reached defaults; its temporary OwnedCString retains normal cleanup.
Remove the three in-place mode wrappers and retain the unique open operation
with an explicit mode. Migrate all callers and examples rather than retaining
compatibility facades. Generic copy_c_string selects Allocator evidence directly
and checks terminator-size overflow before allocation. No compiler phase changes
are needed. The ordinary overload inventory falls from 23 to 19 repeated names after migrating whole-file reading.

Validation exposed legacy erased-Allocator signature selection in read_file after
the opening migration. Move all four read_file overloads to FileReading with
PathValue and Provider participants. Reuse the private algorithms as generic
operation aliases, keeping the allocator static through path conversion and
whole-file reading. This removes another ordinary family rather than extending
the legacy erased overload path. Keep conversion, stream errors and cleanup.

Generic operation alias validation then isolated a missing choice-literal argument
context: input instantiation encountered ..read before the ordinary callee's
known signature could supply FileOpenMode. Supply choice argument context from a
single visible concrete ordinary function, before instantiating its input record.
Do not rank overloads, inspect cached generic instances or infer from outputs.
Named/positional and narrow optional payload regressions cover the behavior.

A range probe found that contextual generic choice payload records accepted 256
for UInt8 when failed coercion left the literal at Int32. Reuse the stored-value
contextualizer for generic typed literals, retaining their destination width for
the existing safety range diagnostic. Rename the array-specific helper to reflect
its shared role; do not introduce a second range checker. Whole-file reading still
uses the existing String capacity/growth helpers internally; replacing their
erased allocation interfaces remains separate follow-up work.

Final validation: four focused file/choice cases passed, including rejection of
an out-of-range UInt8 choice payload. The broad contract/system/I/O/string and
cat/word-count run passed 453 program cases (1 optional skip), without failures,
leaks or error logs. Optional native Python coverage and the CSV report example
passed 17 cases without skips. The complete internal suite passed 375 tests
(1 skipped). Emitted LLVM contains direct PageAllocator and RefusingAllocator
calls for temporary C-string preparation. Nineteen repeated ordinary names
remain; global overload ranking and legacy Abstract compatibility are not yet
removed.


### Directory enumeration migration

Replace the ordinary next overloads for Directory and DirectoryWalker with
DirectoryEnumeration#(State, Provider). Associate Item and retain filesystem
errors and optional end-of-stream results. Reuse the native algorithms as unique
generic aliases, preserving reached allocator selection, native name copying,
walker frame cleanup and depth limits. No syntax or codegen changes are planned.
The remaining ordinary overload inventory contains eighteen names.

DirectoryEnumeration associates Result as well as Item to preserve the existing
nominal Nullable result for Directory and structural optional result for the
walker. The generic regression projects both elements, exercises explicit and
reached providers, copies an entry name, checks allocation rejection with a
concrete RefusingAllocator, and confirms sticky EOF for a depth-zero walker.
Final validation passed 308 contract/directory/word-count program cases, without
skips, failures, leaks or error logs. Emitted LLVM specializes enumeration for
PageAllocator and RefusingAllocator and selects the walker operation statically.
No compiler code was changed in this batch. Global ordinary ranking and legacy
Abstract compatibility remain pending removal.


### Distinct system queries

Separate environment name lookup from native address indexing: lookup_environment
is one generic ordinary function, while address_at is one concrete ordinary
function. Environment lookup retains its static allocation Provider through
copy_c_string; address extraction still copies checked native bytes. Rename every
caller and remove the get definitions rather than retaining overload wrappers.
No compiler phase changes are needed. Seventeen repeated ordinary names remain.

Focused system query validation passed all four environment/network cases,
including missing environment names and out-of-range address indexing. The
rename creates no new contract identities or dispatch paths.


### Linear algebra operation identities

Replace dot, scale, transpose and dynamic matrix/vector get/set overloads with
scoped capabilities. DotProduct associates a scalar or fallible scalar result.
Fixed scaling/transposition and allocating counterparts select only their own
applicable identities; allocating protocols retain a static Provider and reached
default. MatrixAccess and VectorAccess keep distinct coordinate signatures and
associated Element context. Reuse the unique generic algorithms as aliases.

Qualified module calls now filter operation identities as well as ordinary
functions, in concrete and specialized bodies. The filter must retain ambiguity
inside one module and must not admit another visible module's identity. Positive
and negative regressions cover module filtering and explicit contract selection.
No syntax change is required. Twelve repeated ordinary names remain.

Linear-algebra and module-qualified identity validation passed the full contracts,
more and modules groups. The full internal run passed 374 tests and skipped one,
with the cache-reuse test failing while core source edits were in progress. Its
focused stable-workspace rerun passed both selected internal tests. The four
filesystem consumer cases also passed with the new capability prototypes.


### Remaining filesystem operations

Move exists/remove/rename/write_file into path capability modules, reusing unique
algorithms. Borrowed terminated paths select provider-free capabilities; view
paths select allocating counterparts with a static Provider and reached defaults.
Keep the existing call syntax, output labels, errors and temporary ownership.
Remove redundant allocator arguments from borrowed Path operations. The four
original overload families are gone; eight repeated ordinary names remain, all
in core/maps. Regression coverage exercises generic borrowed paths, String/Path
projection, reached provider selection and allocation failure before side effects.

Filesystem validation passed seven selected path/stream cases without skips,
failures or leaks. View rename/write adapters now use ordinary error propagation
instead of assigning incompatible Errable reason sets; this preserves tracing
and promotes failures through the established conversion. Borrowed path variants
continue to allocate no temporary text.


### Map operation migration

Replace every map get/contains/get_ro_ref/put/remove/insert/reserve/extract
ordinary family with scoped capabilities. Selected containers associate Key and
Value, supplying narrow literal context before alias specialization. Owned
containers retain borrowed query keys and by-value moved insertion keys. Text
lookup uses explicit borrowed StringView capabilities. StringHashMap normalizes
all accepted StringMapKey representations once and shares one get/put algorithm;
get now consistently labels its output result. Allocation operations select a
static Provider and keep reached defaults. Preserve native algorithms, table
shape anchors, lexical cleanup, recursive structural ownership and errors.

No repeated ordinary names remain in core or more. The compiler's old ordinary
ranking and legacy Abstract fixtures still require migration and removal.

Map validation passed 458 contract/collection/word-count program cases without
skips, failures, leaks or error logs. Narrow UInt8 key/value regression covers
associated context, generic lookup, borrowing and removal; StringHashMap covers
normalized literal and borrowed view keys. Existing negative ownership and table
shape tests remain enabled. Emitted LLVM retains selected concrete map aliases.

### Preparing removal of legacy safety adapters

Allow unary explicit contracts to declare storage domains, and implement members
to carry a where mapping. Keep mappings on the selected conformance template;
resolve them through that evidence for static proofs and virtual construction,
using the existing domain path validator and ownership proofs. Reject multiple
participants until domain receivers can be identified explicitly. Verify mapping
metadata in module graphs and bump the snapshot codec version for the added field.

Allow unary virtual interfaces to bind associated types and constants. Their
selected conformance must match all bound elements; operation candidates bind
that interface's associated arguments before signature checking. Preserve frozen
selected implementations and declaration-derived runtime safety summaries.
Positive owned storage, generic domains and bound association regressions, plus
negative domain alias and association mismatch cases, cover the prerequisites for
migrating legacy Abstract safety fixtures. Legacy adapters remain pending removal.

Modern virtual prerequisites passed five focused cases; the full internal suite
passed 375 tests with one skip. A broad migration of 218 simple unary fixture files
preserved existing safety checks: the first pass ran 1,186 successful cases with
two diagnostic-expectation failures. Output mismatch reports conformance failure;
erased receiver invalidation now consistently uses the same mapped-domain
restriction for explicit and legacy declarations. Four corrective/numeric cases
passed after updating expectations and giving numeric test helpers unique names.
Generic Errable reason-pattern inference remains outside this fixture migration.

Final fixture validation passed 1,190 polymorphism/ownership/types/contracts/module
and numeric program cases with no skips, failures, leaks or error logs. Migrated
simple unary and tuple conformances explicitly bind operation aliases, associated
elements and storage mappings. Bound virtual calls complete their input signature
with the interface's associated bindings, not just its erased participant. Generic
associated and storage-virtual regressions pass. Remaining complex legacy forms
and ordinary dispatch fixtures are separate pending migration work; compiler
compatibility adapters are not yet removed.


### Imported identities and non-leading unary receivers

Migrate imported capability fixtures, concrete/generic selection, nominal policy
lookup, composition and tuple association order to scoped operation identities.
Missing operation and repeated conformance negatives now exercise explicit
implementation validation rather than global ordinary lookup.

A generic unary constraint with named associated bindings describes an interface,
not a participant tuple. Infer its participant from the requirement's actual
receiver, select its evidence, and check the requested associated bindings. Apply
the same binding check to virtual receivers. Preserve non-leading receiver safety
proofs when another argument has the same concrete type. Static and virtual
negative regressions reject contradictory interface bindings.

Focused migration cases passed. Broad contract, polymorphism and module validation
passed 678 program cases without skips, failures, leaks or error logs. The full
internal run passed 375 tests with one skip. Legacy compatibility removal remains
pending the remaining complex fixtures and embedded compiler tests.


### Multiline safety and remaining ordinary fixture families

Migrate 38 multiline unary fixtures to explicit participants and bound operation
aliases while retaining conditional consumption, relocation and output guards.
Shared concrete/generic unary associated evidence now uses one conformance per
pattern; identical patterns are rejected even when associated bindings agree.
Contextual choice tests select associated Tag through an input Number participant;
ambiguity between two operation identities remains independent of specialization.

Migrate association projection cycles/dependencies, matrix dimension evidence and
array summation families. Ordinary copy helper names are distinct and still grant
no implicit copy permission. Native callback bodies also retain unique identities.
Concrete/generic defaulted selection uses conformance specificity, with separate
identity ambiguity in the negative case.

Validation passed 338 polymorphism/shared-association/virtual ownership cases and
19 focused projection, dimension, copy, default and native callback cases, without
skips, failures, leaks or error logs. These are fixture migrations; global ordinary
ranking and remaining legacy adapters are still pending removal.


### Removing ordinary specificity ranking

Ordinary identity validation now covers both declaration spellings and all
compile-time arities. Dormant duplicate runtime and compile-time declarations
are negative regressions: both built before the guard and are now rejected.
Remove concrete and generic ordinary specificity ranking, including the generic
structural score implementation. Keep applicability, reached defaults, inference
rollback, unique declaration identities and deferred candidates. Count a generic
probe by its declaration so a shared representation cannot manufacture ambiguity.
A local concrete function and a distinct bundled generic identity are ambiguous;
a focused negative regression observes the former concrete-first behavior.

Ruling: retire the TCP write_all copy and scope read through BufferReading — both
native read functions overlap the Reader fallback under identity resolution —
cost if wrong: callers would receive different error types or byte-level instead
of native reads. Selected File/TCP conformances retain their native algorithms
and exact result types; the generic conformance retains the Reader fallback.
Static adapters can use a different fixed virtual wrapper type as a participant,
without treating its existing interface as the adapter's erased interface.

Migrate imported conformances into their owning modules, imported composition,
remaining defaults/ambiguities and virtual marker fixtures. Remove the syntax
identity-definition marker and bump the frontend snapshot format to 54. Two
embedded tests that used ordinary overloads were observed failing at the new
identity guard and now pass with unique helpers/scoped operations.

Validation passed 682 contract, polymorphism and module program cases without
skips, failures, leaks or error logs; the full internal suite passed 375 tests
with one skip. Final focused checks passed native network/file reads, identity
guards, virtual static adapters, LSP navigation and input identity matching. Legacy Abstract/satisfies/Self compatibility remains a separate pending
removal gate; it must not be described as complete.


### Explicit capability parameter migration

Replace abbreviated capability inputs in 28 bundled/official library files with
ordinary compile-time type parameters and explicit contract bounds. Preserve
runtime signatures, reached defaults, operation evidence and ownership algorithms.
No Reader/Writer/BlockReader/BlockWriter/Allocator/Deallocator/ErrorTracer input
uses the implicit abstract-parameter lowerer in these libraries anymore.

Migrate remaining straightforward unary positive/negative fixtures and embedded
module tests to explicit participants, including imported bounds, nested input
types and canonical associated evidence. Preserve meaningful virtual receiver
and safety declaration failures. Focused internal checks passed five tests and
two imported-bound tests. Broad library/fixture validation passed 529 cases with 0 skips and no
failures, leaks or error logs. Do not remove the legacy normalization path until
the remaining fixtures are migrated.
