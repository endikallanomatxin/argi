# Comparison contract adapters

## Findings

The existing conformance system supports a generic implementation of one contract
conditioned on another contract, including a relation between several participants:

```argi
implement#(
    .Left: Type: ThreeWayComparable#(Left, Right, Args),
    .Right: Type,
    .Args: Type
) Comparable#(Left, Right, Args) (
    .less = (.args: Args) -> (.ok: Bool) {
        ok = is_less_order(
            ThreeWayComparable#(Left, Right, Args).classify(.args = ~args).order
        ).ok
    }
)
```

These names are experimental. The classification includes incomparable values;
`ThreeWayComparable` is not a proposed final public name.

Isolated executable probes against committed branch HEAD confirmed:

- The generic adapter runs when all participants are explicitly supplied.
- A concrete implementation wins over the adapter.
- A generic implementation with a more specific nominal participant pattern wins.
- Missing base evidence rejects the adapter.
- Counters verify which implementation actually executes.

The probes live under `/tmp/argi-comparison-investigation/` and do not depend on
experimental operation-default support in the working tree. They cover one
predicate; the other predicates can use the same adapter structure.

## Inference limitation

An unqualified call with only an Args input does not currently recover Left and
Right through the adapter's constraint. The qualified version executes, while
`less(.args = (...))` reports that no matching operation exists.

Operator argument inference likewise binds participants from implementation Args
patterns. An adapter whose Args pattern is a free type parameter does not describe
how the operands bind Left and Right. Its constraint is checked after input
inference; it is not an inverse evidence search. Therefore the successful explicit
probes alone do not demonstrate automatic operator integration.

A production implementation must resolve this input-inference issue while
preserving ambiguity checks, reached capabilities and the rule that associated
results never infer participants. Do not add an operator-specific fallback registry.

Specificity compares participant patterns. Two identical participant patterns do
not become ordered merely because one has an additional constraint. Such patterns
are rejected as equivalent; concrete and narrower nominal patterns are supported.

## Design consequence

Separate contracts can express the required specialization with existing
conformances. No optional operation or default-operation mechanism is necessary.
A blanket implementation supplies all derived predicates; a specialized
implementation supplies the complete predicate contract. Reusing individual
ordinary helpers remains explicit.

## Adopted interface

The final comparison interfaces take Left and Right directly and omit Args.
Operators supply the actual operand types as participants. The adapter's complete
participant tuple is therefore known before checking its Compare constraint; the
prototype's Args-only inference limitation does not apply. Args remains an ordinary
participant of other existing contracts, including Init and arithmetic operators.

## Validation of the adopted model

- Debug internal suite: 389 passed, 1 skipped.
- ReleaseSafe program suite: 1954 passed, 11 skipped, one outdated diagnostic
  expectation. After updating that expectation, the focused rerun passed; all
  1955 program cases are verified.
- Nine new fixtures cover derived predicates, mixed operands, specialization,
  single classification evaluation, NaN, operand context, foreign equality,
  result signatures, private hooks, explicit borrowing and total-order constraints.
- LLVM inspection confirms direct ordered floating predicates for scalar operators.
- Official formatting checks pass for core, more and the new fixtures.
