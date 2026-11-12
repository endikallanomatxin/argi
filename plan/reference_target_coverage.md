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

## Write-conservation gates

A further reduction shows that incomplete virtual destinations are not the only
case. Two independently named `Slot` inputs can alias, even though each has a
complete entry-relative symbolic identity. Writing through one name does not
justify reusing another name's old contents. The same helper is safe when the
caller provides distinct slots, so rejecting its body unconditionally would
replace the soundness gap with a false positive.

The [alias-coherent storage rule](resource_abstraction.md#alias-coherent-storage-facts)
is the common requirement. The next implementation must cover this matrix:

| Gate | Required result |
| --- | --- |
| [Aliased inputs](examples/incomplete_reference_write/aliased_inputs/main.rg): read after a borrowed target expires, then repair before return | Reject the aliased call |
| 232: the same helper with distinct slots | Accept and return the independent value |
| 233: repair through one input before reading through its alias | Accept and return the replacement value |
| [Incomplete destination](examples/incomplete_reference_write/main.rg): clearing a known candidate does not clear an unrepresented slot | Reject |
| [Caller read](examples/incomplete_reference_write/caller_read/main.rg): the helper returns before the hidden slot is read | Reject; the obligation must cross the call |
| 234: temporarily store and then replace through the same erased reference value | Accept and observe the replacement through the original slot |
| 229/231 and existing collection/view positives | Preserve acceptance |

The three unsafe reductions are currently accepted in fresh, compile-only
checks. They are not ordinary expected-success tests and must never run.
The three new safe gates compile and execute successfully in the ordinary Zig
fixture harness. No Python oracle, new runtime descriptor or compiler exception
was introduced for this investigation.

### Constraints on the implementation

1. Apply one storage-content update rule to direct/symbolic references and
   unresolved destinations. Do not recognize a particular provider or library.
   Equal observation identities can justify updating that observed slot;
   different identities do not establish nonoverlap.
2. Reuse existing symbolic storage/value facts, typed overlap, alternative joins,
   `InputRoute` and caller alias obligations before adding another ledger.
   A may-target list still needs coverage; it is not an alias partition.
3. Preserve the consequence through summaries and erasure. Updating current body
   facts but publishing the old caller post-value would repeat the same defect
   at another boundary. Capture the selected storage before retargeting a path.
4. Preserve possible retained dependencies; weaken must-proofs that an unknown
   store can invalidate. Do not model loss of content knowledge by ending a
   physically live storage generation or silently losing cleanup responsibility.
5. Do not turn every ordinary reference store into opaque root retention. Argi
   permits an expired reference to remain unused; 232 exercises that freedom.
   Owners and opaque protocols can have stronger cleanup/retention obligations.
6. Do not retain every historical write forever. In 234 the second write uses
   the same unchanged reference value and replaces the first stored reference.
   An origin can be physically unknown while this value identity is stable.
   Such an observation does not grant execution authority, initialization,
   ownership or freshness. Assigning it a symbolic name must not make it an
   authenticated loan target.
7. Use a verified common storage/retention guarantee to bound effects when one
   exists. `depends_on` and `from_storage` currently publish validity/content
   dependencies, not physical membership. `refers_to` currently requires an
   explicit reference input and cannot name an associated region. Do not
   strengthen those clauses silently.

Compare a conservative alias-aware store/join rule with conditional heap
relationships using these gates before choosing a representation. The former
can lose precision; the latter can grow into a history engine. Do not introduce
general ordered effects or alias-partition specialization by default. A finite
abstraction must explain both loss of knowledge and preservation of obligations,
including calls, branches and loops. Public storage guarantees are a way to
avoid excessive inference, not an exemption from the ordinary aliasing case.

## Validation

Implementation checkpoint `89c75cfb2` passes 1,540 Debug internal tests (one
skipped) and 2,622 ReleaseSafe program tests (11 skipped), with no failures,
leaks or error logs. That complete run predates the additional 232/233/234 gates.
The optimized compiler and runner retain each fixture's selected CLI build mode.
Both suites run serially under a 6 GiB process limit. Peak RSS is approximately
576 MiB for internal validation and 2.66 GiB for the program build/run command.
The latter includes rebuilding the optimized compiler and runner.

An initial complete program run rejected both ownership-cycle and opaque
repopulation negatives too early. The final gate challenges retained candidates
rather than replacing wholly unresolved storage protocols. A focused six-program
contrast and the repeated complete suites preserve the original diagnostics.
The accepted residual-write reduction remains explicitly outside these claims.

The write-conservation investigation subsequently passes the three new Debug
program fixtures in isolation, including native execution and unchanged
replacement values. Fresh `--no-cache` compilation accepts all three unsafe
reductions; none is executed. The compiler implementation is unchanged during
this investigation. These results validate the acceptance gates and confirm the
missing checks, rather than demonstrate a corrected store abstraction.

The resulting Debug concurrency/alias selection passes all 328 program tests,
with no failures, skips, leaks or error logs. Runs remain serial under a 6 GiB
process limit; peak RSS is approximately 414 MiB. These include the unchanged
229/231 and collection/view positives alongside the new gates.
