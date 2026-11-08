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
