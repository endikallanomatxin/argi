# Contract operation interfaces

Design proposal for later study; no implementation or syntax change is approved.
Replace open signatures such as `.add: _` with explicit, predictable operation
interfaces. Validate the model before migrating core contracts.

## Proposed rules

- The contract declares every input an implementation may accept.
- An implementation may omit any input, including an operand. Omission means
  ignoring that input; there is no required/optional classification for
  implementation inputs.
- Accepted inputs must match the declared names, types, access modes and Safety
  guarantees. Implementations cannot add undeclared inputs.
- Generic callers supply the complete interface, subject to ordinary defaults
  and lexical `assume` rules. Contracts introduce no separate injection system.
- Supplying an ignored argument still evaluates its expression exactly once,
  with ordinary evaluation order, propagation and cleanup. Owned values must
  be cleaned up; ignoring a reference does not consume its referent.
- Signature conformance does not prove algebraic laws. Omitting an operand has
  the same semantic responsibility as accepting it without using it.

Explore declaring allocator inputs on Add and Multiply. Scalar and fixed-matrix
implementations could ignore them; strings and dynamic matrices could use them.
Code generic over these implementations would provide an allocator.

## Generic operations

Keep conformance selection based on operand participants, such as
`Add#(Left, Right)`. The allocator's concrete type would be a compile-time
parameter of the operation, not another contract participant.

This requires contracts to declare generic operations and verify that their
implementations satisfy the promised genericity. If an operation promises any
provider satisfying Allocator, an implementation must support that range or
ignore the input; requiring only ArenaAllocator would not satisfy it.
Ignoring a provider should not require specializing the implementation body
for every provider type, though a call adaptation may still be specialized.

## Questions to resolve

- Define operation-level compile-time binders, constraints, input inference and
  implementation matching. Do not restore unconstrained open signatures.
- Specify the relationship between associated Result and provider parameters,
  including fallible allocation, without output-based conformance selection.
- Decide whether calls with an already-selected implementation can omit inputs
  it ignores. Missing capabilities must not become a selection preference.
- Specify named/positional arguments, defaults and implicit supply consistently.
- Model argument adaptation through ordinary aggregate input checking and
  storage/cleanup plans, without structural equality between nominal types or
  backend-specific evaluation rules.
- Define effect checking for ignored owned inputs, fallible evaluation and
  cleanup, including capabilities required by destruction.
- Establish which generic interfaces can be virtualized; do not assume arbitrary
  operation-level specialization fits a finite runtime method table.

Start with a fixed interface and omitted inputs, then operation-level provider
genericity. Exercise scalar addition, string concatenation and fixed/dynamic
matrix multiplication, plus ignored inputs with effects and resources. Compare
native and VM behavior and preserve speculative rollback.
