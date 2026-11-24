# Virtual capability binding

A virtual view selects contract evidence and binds arguments of its operations.
The public interface is the residual signature together with the effects of
calling it. Participant parameters that remain visible must have fixed values
in the virtual type. A hidden participant may be the entire reference type.

## Interface construction

For each operation, record the captured input positions and map every other
position to the residual signature. Determine this mapping when preparing the
interface. Use the same mapping for arguments, results and safety recipes.
Reject hidden types that still determine a public input or output layout.
A dispatch such as `provider.deallocate(.memory = memory)` evaluates the
descriptor once and borrows the descriptor slot for reading. Replacement of
the descriptor uses ordinary writable storage.

The concrete adapter fills captured positions and forwards the remaining
arguments. It uses the selected function's actual reference permissions and
calling convention. A single direct reference can occupy the context pointer.
Multiple independent captures use a borrowed context record with an explicit
storage lifetime. Copying the descriptor copies its context and table pointers.

For joint capture, borrow a record whose fields bind the erased participants
by name. For example, `Virtual#(CopyBetween)(&context)` can bind `.Source`
to an ordinary read reference and `.Destination` to an ordinary mutable
reference. A method signature with `(.destination: Destination, .count:
UIntNative, .source: Source)` exposes only `.count`. The adapter selects
each reference from the corresponding context field in implementation input
order, including when another method declares those inputs in a different
order. The existing single-reference constructor still binds a unary
participant directly.

The context borrow must keep the selected field values stable. A design
that permits retargeting a capture slot must reestablish its effects and
authority before dispatch. Capturing two references does not establish their
independence. An operation that needs disjointness must preserve its overlap
obligation through the public call.

## Safety and transfer

Translate each captured input path into a path rooted at the corresponding
capture. Preserve slot accesses, referent accesses, dependencies between
captures and output provenance independently. A capture carries the authority
of the actual argument. Unresolved aliases and incompatible branch alternatives
lose positive evidence. No operation may acquire stronger authority by passing
through the public interface.

Use ordinary facts and symbolic summaries for value evidence. Keep the
contract's fixed public effects, the captured capabilities and pending
execution obligations distinct. An owned transfer requires a valid cleanup
path and a certified handoff in addition to transferability evidence.

## Integration cases

- Construct one public Deallocator interface with a local mutable reference
  and with a concurrent reference. Exercise ordinary calls and forwarding.
- Use that interface in the same Allocation and String representations.
  Check concurrent submission, local rejection, branch joins, alias
  replacement, accepted cleanup, failed submission and pending execution.
- Bind two references in a borrowed context and test disjoint and overlapping
  regions, output lifetimes and expiry of the context.
- Inspect generated code for descriptor size, absence of runtime evidence and
  unchanged specialization identity for callers that differ only in evidence.

Start implementation at the shared interface preparation path. The current
unary receiver model can coexist while the new interface and its calls are
validated, then bundled contracts can migrate through the new path.
