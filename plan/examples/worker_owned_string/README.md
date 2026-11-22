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
