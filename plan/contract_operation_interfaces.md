# Contract operation interfaces — proposal

Undecided; no implementation or syntax change is approved. Explore replacing
open signatures such as `.add: _` with declared interfaces.

## Intended model

- Contracts declare every permitted input. Implementations may omit any input,
  meaning they ignore it, but cannot add inputs or weaken declared types/access
  and Safety guarantees. No separate optional-input classification is needed.
- Generic callers supply the complete interface using ordinary defaults and
  lexical `assume`. Evaluate ignored arguments exactly once in normal order;
  preserve propagation and cleanup, including destruction capabilities. Ignoring
  a reference does not consume its referent. Algebraic laws remain promises.
- Explore allocator inputs for Add/Multiply: scalar and fixed-matrix operations
  can ignore them; allocating operations use them.
- Keep operand participants determining conformance, e.g. `Add#(Left, Right)`.
  A concrete allocator specializes the operation, not the contract. An operation
  promising any Allocator must accept that range or ignore the input; requiring
  only ArenaAllocator would not conform. Avoid specializing an ignored body
  unnecessarily, though call adaptation may specialize.

## Open design work

- Operation-level compile-time binders, constraints, inference and conformance.
- Associated Result versus provider parameters and fallible allocation, without
  output-based conformance selection.
- Whether a concretely selected implementation permits omission of ignored
  inputs. Missing capabilities must never become a selection preference.
- Named/positional inputs and defaults through ordinary aggregate checking;
  preserve nominal identity and shared storage/cleanup plans.
- Virtualization boundaries: arbitrary generic operations do not necessarily fit
  a finite runtime method table.

First validate fixed interfaces with ignored inputs, then provider genericity.
Use scalar addition, string concatenation, fixed/dynamic matrix multiplication
and ignored effectful/owning inputs; compare native/VM behavior and rollback.
