# Result ownership across a join

Build the directory and run its output. Exit 0 requires all destruction observations. The direct call drops one ticket. Awaiting the first task moves
its ticket into the caller, whose scope exit drops it. A second await must
report already_awaited. Dropping a moved future must join the second task and
drop its unclaimed ticket. The expected count at that point is three. Two further submissions return
the same start error. The first drops the request before invocation and adds
zero destructions. The second executes inline and drops the accepted receipt
before returning the error, adding exactly one. Counter checks
follow synchronous return, successful await or completed scope cleanup.

The worker takes no inputs. Its returned ticket contains a scalar and carries a
cleanup responsibility. Exit 2 records the current unsupported result. Exit 3
indicates failure to start and exit 4 indicates an executor mismatch. A run
ending at submission only exercises the direct-call control.

The existing collection slot operations distinguish establishing storage,
initializing a slot and moving an owner out. A native task output is allocated
before worker entry. Its zero-filled bytes cannot supply a previously
initialized owner for replacement cleanup. The worker must initialize empty
storage; after verified publication the consumer can move the result out or
run its cleanup in place. A failed join provides evidence for neither action.

## Alternative with a typed caller slot

The `caller_slot` probe passes a mutable reference to an initially empty
optional Ticket. The worker returns unit. The direct control moves the
payload out and verifies one destruction. The threaded path leaves the
payload in its typed slot for ordinary scope cleanup after await. It currently
returns 2 at submission. Replacing Ticket with Int32 in the experiment let
the worker populate the choice and the caller read 42 after join. Assigning
to the slot in the caller before await produced a pending-execution conflict.

This separates the remaining type admission problem from native result
extraction. Extending the loan to arbitrary owner-bearing destinations would
be unsound: assigning through the pointer can destroy its old payload on the
worker. A protocol can instead transfer a verified empty destination, constrain
the worker to initialization, and return occupancy and payload dependencies
at publication. Scope cleanup must also handle an executor that ran the worker
but returned an error. A local slot suffices for this scoped experiment.
Returning a movable Future would require stable backing and ownership of the
slot before the fallible submission, with a handoff to the Future on success.

## Stable backing for a movable result slot

The `heap_slot` probe reduces the destination to one initialized Int32 in a
DynamicArray. Its owner stays in the caller until after join. Building it
currently reports “borrowed execution requires an authenticated reference
target” at submission. Replacing submission and await with a direct worker
call compiles, including when the array owner is moved after the call.

This isolates a prerequisite of the typed heap slot approach. Even a scalar
loan needs evidence that every possible referent is covered by the loan and
that other accesses to its backing will see the conflict. A dependency on the
array lifetime alone establishes neither property. A future implementation
should accept this probe and still reject reading the element through a fresh
lookup before join.

### Locating the loss at allocator dispatch

A compile-only comparison at `3755be8d3` kept the executor, provider, slot
construction and worker identical. Each variant initialized the first
UIntNative of an eight-byte allocation, submitted its reference to the writer,
then awaited completion before reading it. Temporary instrumentation counted
possible acquisition origins on the bounded slot in each variant.

| Allocation source in the caller | Origins on the bounded slot | Loan admitted |
| --- | --- | --- |
| `acquire_heap_storage` followed by `establish_allocation` | 1 | No |
| `allocate_bytes(.self = $&allocator, ...)` with a concrete CAllocator | 1 | No |
| The same call with `erased ::= Virtual#(Allocator)($&allocator)` and `.self = $&erased` | 0 | No |

All three use the same final construction:
`trusted_establish_allocation_slot#(.t: UIntNative)(.allocation = &memory,
.slot = raw, .anchor = memory.anchor)`, with the raw address taken from
`memory.data.address`. The dispatch comparison isolates a loss before any
DynamicArray lookup. The concrete control exposes a separate issue: observing
one possible origin still leaves the checker without a loan footprint that
covers every alternative.

For an abstract allocator, acquisition freshness would be an excessive public
requirement: an arena can return a checked subrange of an existing block.
A sufficient storage guarantee would bind the returned view to a live backing
and bound its extent. Two existentially hidden backings must still be treated
as potentially overlapping. Distinct calls, owner roots and executor receipts
supply no proof of separation. This leaves room to lend an entire backing
before supporting parallel writes to disjoint indices.

A compile-only experiment admitted the concrete CAllocator slot whenever it
retained an acquisition origin, leaving the loan's address unspecified. A
second reference obtained by an independent lookup could read after join.
Reading before join and destroying the owner before join both failed to
compile. However, submitting a second writer through that reference compiled:
submission compared two absent storage identities as independent. The
experimental admission was discarded. The shared conflict check now treats an
absent footprint on either side as potentially overlapping for ordinary writes.

Using that conservative overlap rule in the same experiment rejected the
second writer, but also rejected awaiting the first task at the access to
the caller's task handle. This distinguishes the two obligations for a heap
loan. It must cover every possible backing, and the checker needs a verified
separation between that backing and the caller's lexical task-handle slot.
Neither accepting any nonempty origin list nor treating all memory as the
loaned backing meets both conditions.

### Separation from the caller's local storage

The `concrete_heap_loan` control creates two references to the same bytes
before submission. The worker writes through one and the caller reads through
the other after join. This isolates the authority question from erased allocator
dispatch. The following modifications change only the operation before await.

| Before await | Required outcome |
| --- | --- |
| No additional operation | Accept the join and subsequent read |
| Read `alias&` | Reject the overlapping read |
| Submit another writer with `.slot = alias` | Reject overlapping submissions |
| Call `deinit($&memory)` | Reject early release |

A compile-only experiment on the concrete control tested two separation rules.
Recording the lexical frame at lend still rejected await: the local receiving
the task had already been registered when the loan was established. A frame
excluding *later* storage therefore could not exclude the task's own slot.
Assuming the loan covered external backing and exempting direct accesses to
lexical slots accepted the control and rejected the three variants. The
early-release variant failed at the destructor's unknown effects, so that run
does not establish that generation invalidation would independently reject it.

The second experiment assumed the very property the implementation needs to
prove. Its admission rule was discarded. The design target is an all-path
guarantee that the observed range lies in live acquired storage, established
at the physical boundary and preserved through checked subranges. The first
implementation can conservatively overlap all such external loans. Proving
that two distinct acquisitions are independent is optional for this control.
A projected path through a stored reference still needs its own access check.

### Where a checked range can originate

The successful heap acquisition checks the native failure sentinel and address
overflow before packaging its requested extent. The POSIX page producer can
unmap padding on both sides of a mapping before packaging its surviving range.
For both producers the useful assertion is about the bytes in the successful
receipt. In particular, a surviving mapping identity alone says nothing about
whether an address points into the prefix that was just unmapped.

At ordinary establishment the requested prefix is bounded by the receipt's
private size. This is the point at which the allocation can retain coverage
of that prefix. The integer-address establishment path also serves
suballocators. It accepts a size supplied independently of the address.
Sharing the implementation of the two paths must not give the latter the
former's guarantee. The address capability check establishes availability;
its input carries no length against which to validate a supplied extent.

A coverage implementation should distinguish the following cases even if the
same address flows through every call:

| Operation | Guarantee usable for a loan |
| --- | --- |
| Establish a checked prefix of a successful receipt and select an in-bounds slot | The slot lies in the acquired range |
| Establish from the address alone with an independently supplied length | Requires additional evidence of containment |
| Join alternatives from these two paths | Only guarantees common to both paths |
| Establish an empty prefix | No nonempty slot lies in the prefix |

The assertion concerns the backing bytes. Entry authority, initialization,
provider lifetime and release compatibility are separate checks. In particular,
the caller selecting a deallocator at establishment still has to choose one
that can release the storage returned by the producer.

## Where the typed destructor must be authorized

An isolated compiler experiment based on 1cfa69f15 specialized the result
destructor for Ticket and moved the claimed slot out in await. Forming the
destructor address inside the isolated worker failed isolated-callback
verification. Selecting it at submission instead, and passing it to the worker
in the private invocation, got past that check. This kept the callback body
outside worker execution and kept the existing isolation rule.

The remaining diagnostic was at construction of the virtual ProbeExecutor.
Its submit method can accept the request, drop its receipt and return an
error. In this experiment receipt cleanup called the native destroy operation
with unknown effects, since it could run the result destructor. That exceeded
the executor's published access bound. The program was rejected before it
could provide any evidence about successful extraction.

This distinguishes publication from authorization. The native cleanup token
selects a function but carries no static bound for its accesses. Declaring
native destruction to have no accesses would hide Ticket's write to the drop
counter. String adds the lifetime and access requirements of its deallocator.
One design to test is keeping typed output custody at the submitting caller
across the call to submit. Then a failing executor can finish the worker and
release its execution resources while the caller still owns the published
output and can perform checked cleanup after submit returns. On success the
same custody would move into the future. Either design must keep the slot
alive even when an executor finishes or drops a receipt inside submit.
