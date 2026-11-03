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

The private platform runtime supplies joinable native threads. A handle has one
owner; join and destroy are serialized. Join publishes worker writes, and only a
successful join permits destruction. A failed join retains the handle and its
context obligation. Native scalar callback probes exercise compiler-generated
trampolines and join before the caller reads a result. This is not a public
Executor or a permission to transfer arbitrary language storage.

- Define checked cross-thread transfer for values and references. Existing atomic
  cells and cancellation tokens do not authorize transferring arbitrary Argi
  owners or loans. Do not claim general data-race freedom or mutable exclusivity.
- Specify task storage domains and generated Runnable effects for owning inputs,
  borrowed inputs and owned results. Test `retains`, `from_storage` and `empties`
  against real storage receipts. A preservation-only Runnable fixture with scalar
  arguments does not establish that erased owning tasks can be consumed safely.
- Model the checked handoff into a worker callback. Its raw context address must
  carry an authenticated task-storage identity, initialized argument occupancy,
  cleanup ownership and completion outcome through the native boundary. Merely
  rebuilding a reference from that address inside bundled core would invent
  validity; a general C callback's raw arguments provide no such evidence. Join
  must return the resulting state to the same task storage before extraction.
- Expose native thread ownership through checked task storage and transfer
  evidence, including failure to start, completion publication, joining and
  cleanup. Use the shared platform runtime adapters. Add synchronization for a
  reusable worker pool only after ownership at the native boundary is modeled.
- Extend the initial plain-value Future and ThreadedExecutor to owning inputs
  and results only after that transfer protocol is checked. Preserve single
  extraction, join-before-drop and failure cleanup. Opaque receipts currently
  use the native task backend; keep alternate completion strategies behind that
  boundary rather than adding backend types to Future or generic vtable slots.
- Add structured task groups, cancellation, deadlines and interruptible waits
  after basic execution and lifetime rules have executable tests.
- Add System.executor after the VM can retain a virtual capability whose native
  methods are outside its execution subset without eagerly lowering those
  methods. Merely adding the field currently makes unrelated System-based
  compile-time entries and REPL submissions fail on callback-valued signatures.

Use Zig's generated trampolines and typed argument packaging as implementation
references. Preserve Argi's ordinary conformance selection and safety summaries;
do not add async-only function identities, generic vtable slots or manual job
wrappers as a prerequisite for users.
