# Concurrency

## Model

Use ordinary function identities, `inputs_of`, `result_of`, `prepare_args` and
`invoke` to generate task specializations and Runnable evidence. The executor's
vtable stays monomorphic: it schedules an erased task handle, not a generic
function. Network, FileSystem and other System capabilities remain independent.

Prepare arguments in the caller before scheduling. Defaults and assumed inputs
must not be evaluated again on a worker. Keep task arguments, completion state
and the eventual result in stable storage independently of a movable Future.

Prioritize a threaded executor; retain an interface that can later coordinate
event-based waits without making all capabilities methods of Executor. A pending
Future's cleanup must wait for task completion or transfer its storage to a
checked owner. Dropping it cannot free storage still used by a worker.

## Remaining design and implementation

- Define checked cross-thread transfer for values and references. Existing atomic
  cells and cancellation tokens do not authorize transferring arbitrary Argi
  owners or loans. Do not claim general data-race freedom or mutable exclusivity.
- Specify task storage domains and generated Runnable effects for owning inputs,
  borrowed inputs and owned results. Test `retains`, `from_storage` and `empties`
  against real storage receipts. A preservation-only Runnable fixture with scalar
  arguments does not establish that erased owning tasks can be consumed safely.
- Add native thread ownership and synchronization, including failure to start,
  completion publication, joining and cleanup. Preserve optional native boundaries
  and use the shared platform runtime adapters.
- Implement stable Task/Future storage and ThreadedExecutor using that transfer
  protocol. Validate zero, one and multiple outputs, fallible results, partial
  initialization, shutdown and a Future destroyed while its task is running.
- Add structured task groups, cancellation, deadlines and interruptible waits
  after basic execution and lifetime rules have executable tests.

Use Zig's generated trampolines and typed argument packaging as implementation
references. Preserve Argi's ordinary conformance selection and safety summaries;
do not add async-only function identities, generic vtable slots or manual job
wrappers as a prerequisite for users.
