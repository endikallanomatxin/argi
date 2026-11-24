# Delivering an owned String from a worker

Build this directory with `argi build` and run its output. Exit 0 is the
acceptance condition. Exit 2 identifies the current unsupported task payload,
3 a start failure, and 4 an executor mismatch. A sequential control uses the
same factory and provider before submission. The provider outlives the future
and the received owner. The caller makes no competing allocator calls during
the task. A helper consumes the future and returns the String. The caller
checks that the allocator still has live storage, reads the byte and checks
for an empty allocator after scope cleanup. A second submission exercises
abandonment by dropping the future and checking the allocator again.

Public async admission checks both the input (an allocator handle here)
and the output. A single unsupported result does not distinguish which check
failed. The private owned submission path uses a typed caller-owned slot for
extraction and abandonment. Admitting this worker through the public entry
still requires execution authority and transfer of its cleanup dependencies.

Before enabling owning results, the task protocol must establish whether its
output slot contains a live owner, publish that state with the result, and
move or clean up that owner exactly once. Dropping a successful future without
awaiting it must also satisfy the destructor's external requirements. Failure
before worker entry cannot imply that an output was initialized. The provider
dependency must follow the result beyond await if the result outlives its
future. These obligations also apply to owners other than String.

The `input` control exercises the opposite transfer. The caller constructs the
String, moves it into the submission arguments and keeps its allocator alive
until after await. The worker consumes the String and returns a plain byte.
Exit 2 therefore isolates the owning-input admission check from the result
restriction. Exit 0 would exercise the worker's use and scope cleanup. The
returned byte alone cannot certify exactly-once release.

The existing request borrows the prepared arguments and its worker loads a
copy of the input record. Opening the input type gate alone would give the
caller and worker cleanup responsibilities for the same bytes. Submission
needs a single owner on either side of acceptance, including when a provider
returns an error after starting a worker.

The compile-only negative control in `slot_escape` moves the caller's optional
String into a local snapshot, writes none to the slot, and returns the snapshot's
payload. The surrounding factory then returns that String past the lifetime of
its GeneralPurposeAllocator. At 2330f5597 this compiles. Do not execute it.
Both returning the String directly and removing just the write of none from
the generic helper produce the expected local-storage-generation diagnostic.
With a provider that stays in scope through cleanup, taking and emptying the
slot succeeds. A handoff using ordinary moves requires the helper's output to
retain the entry payload's dependencies even as its slot postcondition becomes
empty. This is a sequential prerequisite independent of the task ABI.

## Acceptance cases for an entry observation

| Observation | Subsequent change | Required outcome |
| --- | --- | --- |
| Move a String from an optional slot | Empty the slot, then return the String beyond its provider's scope | Reject the escape at compile time (ownership fixture 321X). |
| Move the same String from the same slot | Empty the slot while its provider remains live through cleanup | Accept the move and cleanup (ownership fixture 322). |
| Obtain a reference to slot A through a virtual getter | Redirect the provider to B, then write through the obtained reference | Update A and preserve B (concurrency fixture 321_exported_reference_survives_retarget). |
| Redirect the provider to B before calling the getter | Write a local reference through the returned reference to global slot B | Reject the store (concurrency fixture 317X). |
| Obtain a reference to a local target | Return the reference beyond the target's scope | Reject the escape (concurrency fixture 322X_exported_reference_outlives_target). |

These cases distinguish the contents taken from a slot, the identity of a
reference already obtained, and a later query through the provider. An
implementation may forget the provider's earlier route after observing its
target if it preserves the obligations of the observed value. A new call
must account for changes that could affect its own observation.

## Evidence available at the worker boundary

A temporary inspection of the converged summary for the direct make_text
control at 2ed86c48c found one output with a fresh owned root, a cleanup
obligation and an input_receiver_values recipe for input zero with an empty
projection path. Its ordinary input_dependencies list was empty. The worker
result therefore already carries a recipe for the erased allocator receiver.
Retaining only ordinary input dependencies when transferring a worker result
would omit the provider. Instantiation needs the submitted argument value
while its receiver and captured dependencies are still available.

The same summary had unknown_access set and no enumerated input or global
accesses. Receiver validity alone cannot authorize running this worker. Any
admission proof also needs an access bound that covers the selected allocator,
including backing providers its operations can reach. Ordinary direct-call
summary instantiation is a reference for preserving the result dependencies;
it does not discharge that separate execution obligation.

The compile-only `await_escape` case keeps the executor in the caller and the
allocator in the factory. The worker result crosses both a consuming await
helper and the factory return. Once submission admits this worker, the factory
return must be rejected for retaining the local provider. A rejection at
submission also prevents the escape but does not test the return obligation.
At 0a955da36 the public entry compiles this example with its unsupported
submission branch. Build this control without running it.
