# Reference observations through checked views

Next implementation gate after b0ca339b6. This is a candidate extension of the
existing reference-summary relation, not an implemented guarantee. Keep the
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

No compiler behavior is changed by this proposal. Dynamic conformances, arbitrary
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
