# Remaining contract dispatch work

The compiler uses unique ordinary functions, contract-scoped operation identities
and selected `implement` evidence. Core and more use Init, Convert, Deinit and
operator contracts. There are no legacy overload, constructor or destructor
registries or implicit participant/representation adapters.

## Remaining design work

- Define joint virtual evidence for several hidden participants, including its
  representation, ownership and lifetime relations.
- Extend symbolic dimension constraints conservatively without inverse inference.
- Specify standard identities for ordered comparisons, C enum equality and
  callback-pointer equality before replacing their representation primitives.

## Independent diagnostic follow-up

Profile conformance verification independently from executable reachability.
Executable builds prove selected operation bodies and reached virtual evidence.
Exhaustive checks and editor diagnostics also prove unused concrete operations.
Reprofile per-module substitution maps and full-pool materialization sweeps
before replacing them with function-local storage or unresolved-item worklists.
Preserve signature binding/default identities and speculative rollback when
changing their storage.

Before reusing validated core graphs or summaries, specify invalidation for
source, target, imports and specialization visibility. Preserve selected operation
identities and all conformance diagnostics.

Signature probes currently collapse some instantiation failures into pending
resolution. Distinguish definite errors from missing bindings without exposing
errors from losing candidates. Explicit and inferred calls now share argument
publication, but their initial inference rules remain distinct.

Verify contextual fixed-array initialization in parameterized ordinary bodies:
`[1]UInt8 = (0)` previously produced an incorrect generic-input mismatch. Keep
this issue independent of contract evidence and virtual representation.

## Validation

Use focused contract, polymorphism and editor checks with parallel workers,
then the complete regression. Preserve selected-evidence rollback, associated
signature checking, virtual safety proofs and cold/warm frontend equivalence.
