# Reference target coverage

## Rule

A retained target set is a set of possible destinations, not automatically an
exhaustive set. In particular:

    known target JOIN unknown alternative != one definite target

Copying a reference does not create authority. Losing one of its possible
origins cannot justify a strong update, definite initialization, generation
renewal, consumption, a new execution loan or an exact captured-region claim.
This applies equally to temporal body facts and published function summaries.

This is distinct from preserving a common observation: every alternative may
share a verified backing relationship without identifying one exact subobject.
The existing reference relations and lexical observations remain useful. Neither
lifetime dependencies nor the absence of a known target proves disjointness.

## Representation and composition

`ValueFacts.reference_target_incomplete` records that a represented reference
alternative has no retained target identity. `ValueEffect` transports the same
uncertainty through summaries. The marker is not a permission, runtime tag or
claim that every unmarked value has a complete target abstraction.

Erasing all known candidates would lose possible mutations. Treating every
retained union as exhaustive would authorize unjustified definite updates.
Keeping one uncertainty bit alongside the existing candidates preserves that
distinction without a second permission ledger or new runtime evidence. A
function-wide unknown-access bit cannot replace value-level target coverage.

Two operations must remain distinct:

- Metadata accumulation combines evidence about one value. An empty accumulator
  does not contribute an unknown reference alternative; an existing incomplete
  marker remains incomplete.
- An alternative join describes a value selected from multiple executions of
  control flow. A known target combined with an unknown target is incomplete.
  Its known candidates and possible validity dependencies still matter.

`OutputAlternatives` copies its first returning alternative and joins later
alternatives componentwise using the completed output type. It must not treat
its empty accumulator as an actual unknown branch or use accumulation as a
branch join. Joining identical effects is idempotent and introduces no new
storage-authorization requirements. Existing typed joins handle records, arrays
and variants; no new selection-syntax recognizer is involved.

The uncertainty marker survives copies, summary substitution, guarded summary
comparison and convergence equality. At instantiation, missing input reference
targets contribute uncertainty too. A verified reference relation can preserve a
universal observation even when the source's exact target set is incomplete.
The 177/197 view tests exercise this distinction.

## Consumers

An incomplete symbolic singleton only supports a weak update of its known
candidate. It cannot erase that candidate's old reference dependencies. Candidate
updates use alternative joins, retaining both previous and written values.

Execution access checks use the existing unknown-footprint rule rather than
checking only known symbolic candidates. Read/read remains compatible; a verified
common observation can still exclude genuinely independent later storage. New
loans require authenticated targets for every alternative.

Initialization, renewal, consumption, owning replacement and exact receiver
region selection cannot use an incomplete singleton as definite evidence. Reads
of resource/reference-bearing storage through such a selection are rejected;
scalar reads discard candidate-only tag and selector refinements. Native scalar
reads do not inherit task-transfer restrictions merely because both mechanisms
need to distinguish plain values from values carrying resources.

This gate only challenges a retained candidate set that could be mistaken for
one exact destination. Wholly unresolved storage still needs its existing
opaque/native protocol; the marker neither replaces that protocol nor makes it
valid. The ownership-cycle and release/repopulation negatives must continue to
check their actual storage obligations, not stop at a candidate-selection error
when there is no candidate to select.

Derived views forget exact target claims. Only an existing checked exact-offset
proof can recover a concrete subobject. No runtime representation changes and no
new ownership or synchronization guarantees follow from these rules.

## Regression evidence

The old checker strongly replaced the only retained symbolic candidate after a
known/unknown join, dropping its previous reference dependency. The production
unit test fails before the change and preserves both dependencies afterward.

- 228X retains a temporary reference in the original slot when the uncertain
  write may select another provider. A later read must reject the expired root.
- 229 performs a definite write to the original slot and remains valid.
- 230X/231 repeat that contrast through a result-returning helper. They require
  alternative-aware summary transport as well as the local update rule.
- Unit tests check joins in both orders, idempotence, copying, authorization,
  lending, tag refinement, initialization and generation renewal.

## Open obligation: the uncovered part of a write

A weak update of known candidates is necessary, but not sufficient. The
[compile-only counterexample](examples/incomplete_reference_write/README.md)
writes a short-lived reference through a known/unknown destination, then clears
only the known destination. A different slot can still hold the expired
reference, while its recorded abstract value remains unchanged. This reduction
is currently accepted; it must never be executed or counted as a safe positive.

The marker closes unjustified definite conclusions for represented candidates.
It does not yet retain obligations or invalidate facts for every unrepresented
write destination. A complete solution needs a conservative residual write
abstraction, a verified closed destination domain, or rejection when the needed
retention guarantee is absent. Guessing physical identity from validity anchors,
or attaching the obligation only to a candidate that can later be cleared,
would not solve the problem.

Further body-witness collection cannot establish coverage by enumerating more
recognized syntax. This open obligation remains ahead of owner transfer and
protected-access protocols. These changes are a bounded soundness improvement,
not a general proof of temporal safety or data-race freedom.

## Validation

Complete validation passes 1,540 Debug internal tests (one skipped) and 2,622
ReleaseSafe program tests (11 skipped), with no failures, leaks or error logs.
The optimized compiler and runner retain each fixture's selected CLI build mode.
Both suites run serially under a 6 GiB process limit. Peak RSS is approximately
576 MiB for internal validation and 2.66 GiB for the program build/run command.
The latter includes rebuilding the optimized compiler and runner.

An initial complete program run rejected both ownership-cycle and opaque
repopulation negatives too early. The final gate challenges retained candidates
rather than replacing wholly unresolved storage protocols. A focused six-program
contrast and the repeated complete suites preserve the original diagnostics.
The accepted residual-write reduction remains explicitly outside these claims.
