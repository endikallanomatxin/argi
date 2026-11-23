# Delivering an owned String from a worker

Build this directory with `argi build` and run its output. Exit 0 is the
acceptance condition. Exit 2 identifies the current unsupported task payload,
3 a start failure, and 4 an executor mismatch. A sequential control uses the
same factory and provider before submission. The provider outlives the future
and the received owner. The caller makes no competing allocator calls during
the task. On success the caller reads the result and drops it before the
provider leaves scope.

The current async admission checks both the input (an allocator handle here)
and the output. A single unsupported result does not distinguish which check
failed. The current await path independently restricts extraction to plain
data. It reconstructs a copy after join. Future cleanup releases native task
storage; it has no typed operation to destroy an unclaimed result.

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
