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

Verify contextual fixed-array initialization in parameterized ordinary bodies:
`[1]UInt8 = (0)` previously produced an incorrect generic-input mismatch. Keep
this issue independent of contract evidence and virtual representation.

## Validation

Use focused contract, polymorphism and editor checks with parallel workers,
then the complete regression. Preserve selected-evidence rollback, associated
signature checking, virtual safety proofs and cold/warm frontend equivalence.
