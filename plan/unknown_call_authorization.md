# Uniform unknown-call authorization

## Invariant

Unknown access is an upper bound over possible accesses, never an empty set.
When an execution retains any caller loan, an unknown call must be rejected
before applying completion or cleanup postconditions. Direct native imports,
virtual calls, ordinary wrappers and selected cleanup use this rule. No library
name exempts a call. Loan-free executions and sequential unknown calls remain
unrestricted by this particular check.

## Preserving the acceptance cases

- Evaluated reference snapshots retain explicit field/variant observation paths.
  Readonly reference inputs can select stored reference leaves when the complete
  summary establishes that their sources remain stable. These paths load actual
  caller values; the enclosing record's observation is never inherited.
- Audited offsets preserve backing only under their existing same-live-region
  precondition. They prove neither containment nor exact target identity. Pure
  dependency attachment and readonly reference copies preserve the source relation.
- Allocation now retains an optional private reference to its authenticated byte
  backing. This is physical representation evidence, not acquisition permission,
  initialization evidence or a lifetime-derived independence claim. Empty byte
  reservations have no witness. Heap establishment and arena suballocation must
  initialize it only after acquisition/range validation. Public address mutation
  cannot redirect the witness, and existing private range checks still apply.
  This adds a runtime field to Allocation; Virtual remains two pointers. This cost
  is explicit: an erased producer's scalar address/lifetime cannot provide the
  missing physical observation without a verified representation invariant.
- A backing access is recorded separately from direct access to a witness slot.
  At calls it uses the selected observation conservatively, dropping exact slot
  identity. Its lexical observation can exclude independently later concrete
  storage, never unknown symbolic, global or earlier storage. Access bounds on
  ordinary subobjects cannot silently authorize an entire backing.

## Retargeting and composition

A reference-slot replacement has a known write footprint; it is not inherently
an arbitrary memory access. Replacing reference-bearing storage disables old
observation publication. If accesses traverse a possibly retargeted slot, the
summary remains unknown rather than guessing an ordered alias history.

Known local helper destinations receive the existing definite post-value.
Multiple possible local destinations receive an alternative-aware weak join of
the old and replacement values. A write whose copied local destination cannot
be resolved must remain unknown: omitting its external footprint is not enough
when later returned facts could still describe the old local value. The 201/204
positives and 200X/202X/203X negatives distinguish these cases. Sequential mutable
aliasing remains available; unknown effects only meet the new restriction while
caller storage is lent to another execution.

Numeric induction without reference-route changes can retain known footprints;
loops with potentially changing targets remain conservative. This does not add
a general ordered-effects model.

## Limits and proof boundary

The private backing reference describes uninitialized backing without reading it.
It cannot escape ordinary code independently of the allocation; selection retains
owned-root and anchor dependencies. Raw construction remains an audited core
obligation. Moving a receipt does not recreate acquisition permission. Loading a
reference stored inside an element must use that reference's observation, not the
container's construction time. Zero-sized slot selection and unknown aliases stay
conservative. No owner-transfer, mutex or general ordered-effects guarantee follows.

## Validation status

The broad checkpoint passes 1,524 Debug internal tests (one skipped) and 2,595
ReleaseSafe program tests (11 skipped), with no program failures, leaks or error
logs. A final selector audit then added a failing-then-passing production unit:
backing footprints must select evaluated fields instead of reloading aggregate
provenance. Both output relations and backing accesses now use the same explicit
projection walker. The final 317-test Debug safety run and 214 affected
concurrency/executor program tests pass, with no failures, skips, leaks or error logs in that selection.
The final selector increment was revalidated with these focused suites rather
than repeating unrelated full-suite cases.

Unchanged 121, 177 and 201 remain positive acceptance cases, alongside 204. The
unknown virtual/native/callback/wrapper/cleanup cases and retargeting reductions
are negative checks, never executed as unsafe programs. All validation is serial
under a 6 GiB process limit. These results do not establish general concurrent
soundness. Owner transfer, protected-access protocols and general physical
containment through erased interfaces remain outside this checkpoint.


## Reference-mutation follow-up

[The mutation checkpoint](conditional_reference_mutation.md) addresses a separate
composition issue found after this gate: stale local reference values could
escape before lending began. The access gate cannot compensate for an inaccurate
value summary. Its regression matrix covers conditional replacement, returned
and stored aliases, reassignment, caller-local updates and mixed target kinds.
