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
