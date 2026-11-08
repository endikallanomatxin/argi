# Reference observations through checked views

Implementation gate following b0ca339b6. The rules below specify a candidate
extension of the reference-summary relation. The initial checked-array output
implementation and its validation status are recorded at the end; general
physical-backing transport remains open. Keep the
unchanged concurrency/121 heterogeneous DynamicArray program as the acceptance
target with uniform unknown-call authorization enabled. A precomputed view is a
reduction, not a replacement API requirement.

## Reproduced requirement

The [pending positive reduction](examples/reference_backing/main.rg) (local
concurrency/177) creates an ArrayView of initialized integers before lending an
unrelated later local to a worker. Calling get_reference while the worker runs
returns a valid reference, but its subsequent read is rejected for an unknown
footprint. This reproduces without allocation, Virtual or the unfinished unknown
call gate. The old backing observation is lost through the checked derivation and
its summaries; observing the reference at return is too late to prove separation.

The missing fact is a relation to the observed backing, not a new permission.
A lifetime dependency on the view, allocator or anchor does not supply it.

## Relation and interpretation

Use the existing caller-relative InputPath vocabulary. Conceptually, an output
reference can publish one of these guarantees relative to an input observation:

| Guarantee | Interpretation |
| --- | --- |
| Identity | The returned reference is the same reference value |
| Contained derivation | The returned reference's complete accessible extent belongs to the backing certified by the source observation |
| Unknown | Neither universal relation has been established |

Identity implies contained derivation only for the source's certified extent.
A contained derivation does not preserve an exact Place, stored contents, named
regions, initialization, ownership or available authority. It can preserve the
earlier backing observation used by lexical-frame separation. It cannot make an
unknown execution-loan target authenticated. Keep the 169X/170X/172X regressions.

This relation describes a semantic guarantee, not the final field layout. Prefer
one graded source relation to two independently maintained source trackers.
Existing exact-forwarding consumers must continue requiring identity. Frames
stay local to a proof namespace; summaries carry source relationships, never raw
frame numbers. If no source relationship is proved, the current conservative
call-return observation remains valid.

## Where the evidence comes from

A checked derivation needs both an existing backing observation and justified
containment of the result's entire extent. Arithmetic alone supplies neither.

| Operation | Evidence it supplies |
| --- | --- |
| Copy a reference | Identity of the copied reference |
| Change only reference mutability | Same storage, with the operations allowed by the result type |
| Checked element/subrange selection | Containment, provided the source backing/length invariant and complete range check hold |
| Widening reinterpretation | No containment from the source's referent type alone |
| Raw-address reconstruction | No source relationship from a lifetime anchor |
| Load a reference-valued element | Facts of the loaded reference, independently of the slot observation |

The existing trusted offset primitives guard arithmetic overflow. Their comments
require callers to prove same-region membership, but the current signature does
not encode that obligation. Do not publish contained derivation universally for
these primitives merely because both sides have pointer types.

ArrayView's private pointer/length invariant and its accessor's range check can
justify a bounded operation; arbitrary pointer-plus-length input cannot establish
that invariant. Bundled trusted constructors remain an audited boundary until
the compiler can verify their physical construction obligations. State that
assumption explicitly rather than treating a core function name as a proof.
The initial implementation must identify how this evidence enters the summary
before granting earlier observations through checked accesses.

## Composition rules

Let G(o, p, k) mean output observation o is related to source path p with grade k.
These are must-guarantees: they hold for every possible successful returned value,
not merely for one dependency contributing to a may-effect.

1. **Copy:** preserve the relation. Copying creates no authority.
2. **Derive:** a certified contained operation changes identity to at most
   contained. Compose containment only within the certified backing extent.
3. **Substitute:** resolve the input path against evaluated argument facts.
   Compose only proved relationships. A validity-only dependency cannot create G.
4. **Join:** retain a relation only when every possible value of that output
   establishes it. Different sources require a sound set of alternatives or
   conservative loss of the relation; do not choose one known branch.
5. **Project storage:** a checked field/element projection can retain the backing
   relationship for that storage. Record fields and array indices remain distinct.
6. **Load contents:** a reference read from a slot has its own observation. Never
   inherit the frame or source relationship of the containing slot.
7. **Retarget:** replacing a reference replaces its observation. Entry-relative
   source facts cannot justify a returned relation after a possibly aliasing
   write changes that source. Initially reject publication for such bodies.
8. **Invalidate:** ending the backing's generation still invalidates the derived
   reference. Reclaim and preserved frames do not revive that generation.
9. **Erase:** replacing a concrete receiver by Virtual must preserve published
   source relationships or forget them. The handle slot is not its receiver or
   the backing reached through a stored reference.

These rules reuse the distinction already required for acquisition permissions:
accumulating may-effects is not joining alternative returned values. The fixes
in 86d88738f and b0ca339b6 address that distinction for acquisition presence; they
do not automatically prove contained-reference relationships. All publication,
substitution, projections and joins need explicit tests before using the new fact.
Do not add a second general body interpreter or an ordered-effect graph.

## Decisive tests

| Case | Required behavior |
| --- | --- |
| 177: old scalar view, unrelated later writer, direct and wrapped access | Accept |
| 178X: choice of old view and view of the worker's backing | Reject conflicting access |
| 179X: old view of reference slots, retargeted element points to the worker's backing | Permit a justified slot load; reject the later referent read |
| 180: same retargeted contents after matching reclaim | Accept |
| Widened referent or unknown offset loan target | Preserve existing rejection |
| Backing invalidation or changed intermediate reference | Reject; earlier observation cannot restore validity |
| Unknown return branch, sparse fields and shared success case | No stronger relation than every alternative justifies |
| Known distinct error outcome | Do not discard a proof solely because another branch returns an error |
| Allocation-backed heterogeneous Virtual extraction | Preserve fixture 121 without a library-name exemption |

On b0ca339b6, 177 fails at the scalar dereference, 178X rejects, 179X rejects
already at the slot load, and 180 runs successfully. The early rejection of 179X
is conservative; it is not evidence that future contained-derivation propagation
correctly stops at the loaded reference. Recheck the diagnostic location when
that propagation is implemented.

## Implementation sequence

1. Define the graded relation and its loss-of-information rules against existing
   ValueEffect and InputPath. Test must-guarantee coverage in Zig, including
   sparse aggregates and reference-valued contents.
2. Establish a bounded construction/containment source. Reuse verified reference
   forwarding where it proves the claimed relation; do not relabel dependency as
   containment. Keep native/trusted construction assumptions explicit.
3. Transport the relation through direct checked accessors and ordinary wrappers.
   Make 177 pass while preserving the paired negatives and sequential aliases.
4. Apply the same semantics to authenticated Allocation storage. Its raw address
   and lifetime anchor are insufficient physical evidence. Specify the abstract
   allocator guarantee before adding any descriptor or runtime field.
5. Close uniform unknown-call authorization with the original fixture 121 and
   virtual/native/callback/cleanup negatives. Then reevaluate owner transfer and
   protected-access protocols against the same invariants.

The pending positive source is retained under plan/examples so the published
program suite does not register an expected-success case before implementing it.
Compile the directory with `argi build plan/examples/reference_backing` to
reproduce the rejection. It must become a positive compiler fixture when fixed.

The specification alone grants no compiler authority. Dynamic conformances, arbitrary
precise alias histories, general effect ordering and scheduler changes remain
outside this gate.

Validation of this design checkpoint: the three registered fixtures 178X, 179X
and 180 pass their focused program-test run, with no failures, leaks or error
logs. Direct fresh-frontend checks using the isolated b0ca339b6 compiler also
confirm the outcomes listed above, including the pending positive rejection.
No new full-suite result or implemented backing guarantee is claimed here.

## Whole-reference source selection prerequisite

A focused checker unit exposes a source-selection error before adding contained
relations: a zero-projection forwarded_reference was instantiated using the
summary loader, which implicitly loads the argument's referent. Forwarding an
argument observed at frame 9 could therefore copy frame 1 from the reference
stored in its target slot. The unit observes the incorrect value before the fix;
it also checks that an unknown argument frame cannot acquire stored evidence.

Whole-reference identity now selects the evaluated argument itself. Nonempty
paths retain their existing projection/loading rules; the change grants no new
containment or authority. The primary safety-module run passes 273 tests. The isolated full Debug
internal suite passes 1,506 tests with one skipped, 585,128 KiB peak RSS and no
swaps. Focused Debug reference/concurrency program validation passes 330 tests,
with zero failures, leaks or error logs. These checks validate source selection;
no contained-backing guarantee has been implemented.

## Bounded Zig experiment for relation composition

The test-only [reference observation model](../src/4_semantics/safety/reference_observation_model.zig)
uses the compiler's InputPath and ValidityRootId vocabulary. It does not add a
ValueEffect field or change production authorization. Run it with:

```sh
zig build test-internal -j1 -Dtest-jobs=1 -Dtest-filter="observation model"
```

Its finite universe has two backings, two generations and the three nonempty
intervals of a two-byte extent. It exhaustively checks all observation triples
and pairs of relation grades for composition, and all output alternatives for
same-source joins. Different source paths lose the relation conservatively;
their names never prove disjoint backing. Slot loads use independent stored-value
evidence. Widened extents and retargeted snapshots do not satisfy containment.
Relation truth is separate from validity: equal ended snapshots still require a
separate liveness check.

Four tests pass. Three deliberately incorrect variants were also tested and
failed behavioral assertions: retaining the first join branch's stronger grade,
retaining identity through a contained derivation, and inheriting a slot's
relation when loading an unknown reference. Restoring the intended rules passes
all four tests again. This challenges the rules rather than merely checking
that a particular helper returns an expected tag.

The model assumes that containment has already been certified. It does not verify
ArrayView constructors, runtime bounds checks, summary extraction, source-path
stability across writes, or native physical provenance. Those remain the next
implementation obligations. It therefore supports the candidate algebra, not a
soundness or data-race-freedom claim about the compiler.

## Structural access authorization before output relations

The checked-array reduction (local concurrency/181) initially failed at the call
to its accessor wrapper, before using the returned reference. Call authorization
used projectValueFacts for an unresolved input access. That operation describes
loaded contents and correctly forgets the containing pointer's frame; it is the
wrong operation for an access to embedded storage.

The candidate uses the evaluated argument's reference facts as a conservative
footprint when the argument type is a pointer and every summary projection is
structural (no stored-reference dereference). These accesses stay inside the
referent. Known Places still use their existing precise overlap checks. By-value
records, unknown argument types, named virtual domains and paths crossing stored
references do not receive this fallback. Loaded values keep their separate facts.
No exact target, initialization, acquisition permission or containment summary is
created. In particular, a missing source frame cannot be replaced by a frame from
one of its stored fields.

The positive fixture 182 reads a checked array element through an accessor and
ordinary wrapper while a later unrelated writer is pending. Published 69959b74e
rejects it at call entry; the candidate builds and runs it. 183X lends the actual
array backing instead and rejects. 184X stores a reference to the later borrowed
local inside the older array and rejects the accessor that dereferences it.
The checker unit reproduces the lost source observation before correction and
checks the content-load, stored-traversal, by-value and missing-source boundaries.

This isolates the remaining output problem: local 181 now gets past the call but
still rejects the later element-reference read. Thus embedded-access authorization
needs no new summary relation, while returned-reference observation transport
remains a distinct obligation. The original ArrayView/Allocation gates remain open.

Validation of structural-access authorization: the primary full Debug internal
suite passes 1,512 tests with one skipped (587,612 KiB peak RSS, no swaps). The
isolated Debug reference/concurrency program suite passes 333 tests, with zero
failures, leaks or error logs, including 182/183X/184X. The isolated source excludes
the unfinished unknown-call and loop experiments; staged compiler and fixture
files match that validation tree. This is not a new full-program-suite result.

## Initial checked output derivation implementation

The candidate replaces the exact-only forwarded_reference metadata with one
ReferenceRelation containing an InputPath source and an identity/contained grade.
The bounded experiment uses that same relation vocabulary. Contract refers_to
still publishes identity; no new source clause or runtime descriptor is added.
Summary equality includes the grade and source. Cache format 149 invalidates
previous semantic publications.

A contained relation can now be inferred from taking the address of an ordinary
checked array element. Its index must be a literal or a scalar UIntNative input
for this initial lexical proof, so index evaluation cannot hide additional calls
or reference retargeting. The semantic array-index node already checks bounds.
When it denotes a dereferenced array value, the observation source is the pointer
used for that dereference, not the loaded aggregate value.

Publication reuses the existing complete lexical forwarding proof. Identity
proofs see only identity call links and still require identical pointer types.
Contained proofs may additionally use certified array-address links and callee
relations. Ordinary wrappers compose these links at the summary fixed point.
Unknown/conditional return bodies that the proof cannot establish publish no
relation. Projection of loaded contents clears the relation. Returning a pointer
from a reference-valued element is not an array-address derivation.

Fixture 181 now builds and runs through an ordinary accessor, its wrapper and a
generic accessor during an unrelated loan. 185X lends the actual backing and
rejects; 186X loads a retargeted reference from the older array and rejects;
187X mixes the checked derivation with a conflicting unknown return alternative
and rejects. Existing shifted/widened-loan negatives 169X/170X/172X/173X still
reject unauthenticated targets. A contained relation preserves an observation,
not an exact loan target or direct access authority.

Focused primary safety validation passes 279 tests. The full primary Debug
internal run passes 1,513 tests with one skipped (578,192 KiB peak RSS, no swaps).
The isolated full ReleaseSafe program suite passes 2,558 tests with 11 skipped,
zero failures, leaks or error logs (620,632 KiB peak RSS, no swaps). It runs
serially under a 6 GiB process limit and excludes the unfinished unknown-call
and loop experiments. Staged compiler and fixture files match that tree. A
separate read-only review found no issues in this increment.
Uniform authorization of unknown call effects remains the immediate soundness
checkpoint. This observation increment does not close that hole, and recovering
more view precision must not replace checking unknown effects at every call
boundary, including isolated worker reachability and native calls.
The original ArrayView/Allocation programs remain open: their offset operations
have no universal containment certificate, and relations nested in fallible or
opaque results need their own publication proof. This increment does not make
those programs safe by assertion or solve owner transfer/protected access.

## Isolated callback audit after 954394eaf

Do not infer a second unknown-call hole merely from the late Safety checker
checking only known global effects. The earlier `global/once_verify.zig` pass
checks isolated callback reachability: it rejects foreign/unresolved direct
callees, indirect function calls, virtual calls and nonplain global storage.
Ordinary helper calls and selected cleanup are traversed. The later Safety
pass additionally rejects reads and writes of mutable plain globals.

Compile-only regressions 143X/144X in `c_interop` exercise unknown native and
virtual calls through helpers. They are rejected before native execution.
The native example uses `abs` only to keep linking independent of a custom
runtime; this is a test of the current isolation boundary, not a claim that
`abs` itself races. This closed-world restriction is conservative, and does
not establish a general protocol for sharing foreign state.

An isolated worker adapter can still have `unknown_access` in its inferred
summary: low-level accesses to its certified buffers are not all expressible
as caller-relative input paths. Therefore rejecting every isolated target
whose summary has that bit would break existing supported tasks. The bit is
not itself a proof of global reachability. Conversely, this earlier isolation
barrier does not authorize unknown calls from the submitting execution while
loans are pending. That caller-side hole remains the immediate open gate.

The focused isolated Debug run passes five cases (141X, 142, 143X, 144X and
concurrency/01), with no failures, leaks or error logs. The primary working
tree's unpublished uniform unknown-call check rejects concurrency/123X as
intended, but still rejects safe 121 at `code_at(&array, 0)` and the reduced 177
at the final element dereference. These compile-only results do not close the
gate: the remaining work is preserving sufficient backing evidence for those
safe accesses, not adding another blanket isolated-callback rejection.

## Indexed reference lifetime correction

Replacing the fixed-array view's trusted reinterpretation with ordinary checked
indexing exposed a separate temporal hole. Before this correction, a helper
returning `&array&[0]` could lose its input backing dependency in its summary.
Returning that result from a caller-local array was accepted, both directly
and through a generic helper returning the reference inside a record. These
programs were compiled only, never executed.

The indexed-address summary used `input_place_values` of the array expression.
That denotes loaded contents, which need not contain any resource facts; it
does not preserve the array pointer's backing lifetime. Derive the pointer
from an immediate array-value dereference and apply the existing
`validityOnlyEffect` to its inferred effect instead. This retains temporal
dependencies without claiming whole-referent identity or ownership.

The two fixed-array view factories can consequently use ordinary checked first
element addresses. Compile-time empty/nonempty branches avoid forming an
index-zero address for an empty array. No permission class, runtime descriptor
or additional trusted operation is introduced.

Regressions types/426X and 427X now reject the previously accepted escapes.
Focused isolated Debug validation passes 304 internal safety tests and 27
program cases, including empty views, contracts/287X, and concurrency/181 and
185X--187X. A read-only review found no concrete issues. The isolated full
ReleaseSafe program suite passes 2,562 cases with 11 skipped, zero failures,
leaks or error logs. The serial run takes 29 minutes, with 2,358,104 KiB peak RSS
and no swaps under the 6 GiB process limit. It excludes the unfinished
unknown-call and loop experiments; staged source and fixtures match that tree.
This correction does not close the caller unknown-effect gate.


## Reference relations across abstractions: consolidation checkpoint

### Implemented prototype

`ReferenceRelation` now distinguishes `identity`, `contained` and the weaker
`backing` relation. Backing means the same physical backing and generation,
without claiming containment in the source referent's extent. It grants no
liveness, initialization, ownership, authority or exact execution-loan target.
The production relation owns common-strength, implication and composition rules;
the bounded physical oracle tests those same operations instead of duplicating
them. A common guarantee survives alternative joins only when both sources
agree. Unknown alternatives or different sources discard it.

The weaker grade is produced only by registered address-preserving
reinterpretations when stronger guarantees are unavailable, with a statically
known nonempty source referent. `Any`'s ABI placeholder size supplies no such
extent and is excluded. The trusted operation's existing validity and alignment
obligations remain necessary. This does not verify a widened cast's bounds.
General offsets publish no new backing relation: the earlier broader experiment
was withdrawn because arithmetic and overflow checks do not prove allocation
membership. Raw address establishment and anchors cannot assert the relation.

Whole-output wrappers still use the complete lexical forwarding proof. Links
must imply the grade being proved; backing-only links cannot establish identity,
containment or a virtual `refers_to` promise. Cache format 150 separates these
semantic publications.

Output substitution preserves a relation only when its whole source is supplied
directly by a constant reference input of the caller. Local aliases, projected
sources and symbolic-input overrides remain unsupported. Nested record/choice
publication uses the existing alternative-aware return flow and requires no
unknown accesses or writes to inputs/globals. It introduces neither an ordered
effect interpreter nor another permission ledger. Direct pointer outputs retain
their stricter lexical publication proof.

The resource flow previously combined possible local alias targets using a
may-effect union. A unit test demonstrated that a known aggregate child's
relation could then survive another unknown target. Binding-alias and explicit
dereference loads now use the existing alternative join, seeded with a real
target. Tests cover both target orders, uniform evidence and singleton targets.

### End-to-end checks and remaining composition boundary

| Case | Required behavior |
| --- | --- |
| 190 | Retyped ordinary wrapper preserves an early observation during an independent later loan |
| 191X | Lending the actual backing still rejects the returned-reference read |
| 192X | Retyping wrappers cannot prove a virtual `refers_to` contract |
| 193 | A fallible retyping result preserves its successful payload when explicitly matched |
| 194X | Indirectly retargeting a local reference cannot retain its old observation |
| 195X | The fallible payload remains unavailable during a real-backing loan |
| 196X | An incompatible successful return alternative cannot borrow another branch's guarantee |

Existing 169X/170X/172X/173X offset/extent loan negatives remain required.
The original 193 reduction using `unwrap_or_abort` still rejects. That helper
projects a reference from a by-value choice; this must not be confused with
loading a reference from pointer-reached storage. The current generic summary
loader supports both with implicit loading conventions. Do not preserve an
observation through it until the selected evaluated value is unambiguous.
Explicit `match` is a reduced composition test, not a replacement API requirement.

### Uniform authorization remains the immediate soundness gate

The primary tree's unpublished check rejects unknown ordinary, virtual, foreign,
callback and cleanup effects against pending loans before applying completion
postconditions. It still rejects safe 121 at `code_at(&array, 0)` and 177 at the
returned reference dereference; it is not ready to publish. A focused matrix
passes 41 cases, including 181, await, inline/delegated execution and callbacks,
but that count includes unrelated numeric-filter matches and excludes 121/177.

Temporary instrumentation locates the first unknown footprint in `code_at` at
the dereference of `holder`, returned by collection `get_reference`: neither
caller-relative pointee paths nor local addressed targets are available. It is
not imported from an unknown callee summary in that helper. The virtual method's
`no_access()` bound cannot authorize the preceding handle-slot load. Traces have
been removed. Do not drop that load or infer physical separation from lifetime.

Cleanup pair 188X/189 belongs to the pending authorization change: the published
compiler accepts the unsafe cleanup (compile only, never executed); the primary
check rejects it. The same cleanup after await builds and runs. Earlier isolated
worker reachability already rejects foreign, indirect and virtual calls; a plain
worker adapter can nevertheless have an unknown caller-relative summary because
of its certified native buffers. Another blanket worker rejection is unnecessary.

### Physical storage construction obligations

A future checked backing observation must be independent of establishment
permission and reuse existing temporal dependencies. The following distinctions
are mandatory before publishing a representation invariant through erasure:

| Producer or operation | Evidence obligation |
| --- | --- |
| Native heap/page acquisition | Tie the actual acquired extent to its address; consuming establishment permission must not erase the observation |
| Allocation establishment | Fresh temporal ownership is not physical freshness; retained origin metadata is not reusable permission |
| Arena suballocation | Direct Allocation construction must retain the original block backing and a restricted range |
| Page and typed allocation restriction | Preserve the same backing when restricting size or advancing past metadata |
| Public data/size mutation | Authenticated private backing is distinct from the mutable public view; validate each selection against it |
| Slot/view selection | Checked bounds and alignment must bind the result to that backing, not merely to its lifetime anchor |
| Stored-reference load | Use the stored reference's own observation, never its container's construction frame |
| Abstract factory result | Prove the representation invariant for every producer; a nominal type or private layout is insufficient |

Fixture 428X redirects public `Allocation.data` to another live allocation. It
aborts in the private range guard before reference establishment, as required;
408X covers inflated public size. Generic wrapped-slot pair 429X/430 demonstrates
that existing lifetime facts reject use after allocation cleanup while allowing
use before it, even with a static anchor. No second liveness table is needed.
Receipt-forgery regressions 382X/383X/415X pass, but prove no general physical
invariant for erased results. The original 121/177 acceptance gates remain open.

### Validation and resource use

The isolated Debug safety suite passes 310 tests; the complete Debug internal
suite passes 1,518 with one skip (584,956 KiB peak RSS, no swaps). Focused program
runs cover the new relations, alias alternatives, acquisition permissions and
cleanup boundaries. These results do not validate the primary tree's separate
unknown-call and loop experiments.

Validation runs serially under a 6 GiB process limit. A temporary-storage quota
failure produced no usable test result. Obsolete generated objects were removed
only after the process ended; sources and logs were retained. The validation
cache now lives under `~/.cache/argi-validation` on disk rather than `/tmp`.

Broad program validation initially failed fixture inventory because experimental
177/188X copies were left without registered tests. They are preserved outside
the isolated fixture tree under `~/.cache/argi-validation/pending-fixtures`;
primary workspace versions are unchanged. The full run and focused inventory
recheck must be reported separately, rather than calling the original run clean.

The broad ReleaseSafe program run finishes with 2,572 passed, 11 skipped and one
fixture-inventory failure, zero leaks and zero error logs (2,435,512 KiB peak RSS,
no swaps). After relocating only the two unregistered experiment copies, the
focused inventory rerun passes (one test, exit status zero). Compiler and
registered fixture source did not change between these checks. All staged
compiler and fixture files match the isolated validation tree. This is a full
program run plus a corrected preparation-check rerun, not an originally clean
full-suite invocation. The uniform unknown-effect gate remains unpublished.


## Evaluated reference selection and choice classification checkpoint

A reference-relation source selects explicit fields/variants in the evaluated
argument, without implicitly loading a referent named by aggregate provenance.
A production unit test previously selected an old frame from that storage rather
than the actual snapshot field. Selection now uses explicit value projections;
missing fields, dereference paths and abstract domains provide no observation.
No projected-source producer is introduced by this correction.

The summary reference classifier now consults array elements, fields and choice
variants for nominal/generic as well as structural aggregate representations.
Previously nominal choices with reference payloads could be classified as plain
because they had no record fields. A failing-then-passing unit test covers both
reference-bearing and numeric-only nominal choices.

Experimental embedded-input relation publication and local post-write propagation
are excluded. The former exposed a still-accepted helper-retargeting reduction;
the latter rejected that reduction but broke safe positives. Those experiments
require further work and do not justify enabling broader observations. The
uniform unknown-effect gate and unchanged 121/177 acceptance cases remain open.

Validation on the isolated checkpoint tree passes 312 Debug safety unit tests and
99 filtered program tests (choices and 193/194X/195X/196X), with zero failures,
skips, leaks or error logs. The compiler build succeeds. Runs are serial under
a 6 GiB process limit with the local cache on disk. This is focused validation,
not a new full-program-suite result. Staged compiler sources match that tree.
