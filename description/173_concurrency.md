# Concurrency

The current interface supports restricted borrowed task inputs. General resource
transfer and execution requirements remain under design in
[the concurrency proposal](../plan/concurrency.md).

Argi's concurrency model builds on ordinary function identities and explicit
capabilities. Function metaprogramming generates a task specialization from a
function and a prepared input record. An executor schedules erased tasks through
a monomorphic interface; it does not absorb Network, FileSystem or other System
capabilities.

## Transfer and lifetime obligations

Moving a value transfers its cleanup responsibility. It does not by itself
establish that the value, its destructor or its retained capabilities can be used
from another thread. In particular, an Allocation can retain an allocator's
deallocation evidence, and a nominal owner can retain thread-affine foreign
state. An implicitly copyable value is not automatically thread-transferable.

Task inputs may contain references to recursively plain, reference-free data.
The caller retains the backing storage until completion. Each readonly reference
lends read authority; each mutable reference lends write authority, even if the
worker itself performs fewer accesses. Multiple readers may coexist. A pending
write loan blocks caller reads and writes; any pending loan blocks incompatible
writes, destruction, replacement and ending the backing lifetime. These rules
follow aliases and calls, including wrappers. A loan must end within the loop
iteration that created it.

`is_borrowable_data(.type = T)` recognizes plain nonowning input records and
arrays with eligible reference leaves. Referents must be recursively plain and
reference-free; destructors, raw pointers, callbacks and virtual handles are not
eligible, and choices containing references are unsupported. Task results must
satisfy `is_plain_data`. Unsupported input or result types return
`unsupported_task_value` before a worker is created. These shape queries do not
by themselves grant access authority or transfer an owning resource.

A receipt identifies each pending execution and its actual storage generations.
Successful join publishes the worker's writes and completes only that execution's
loans. Failed submission creates no pending loan, while failed join retains it.
Pending execution receipts cannot be stored in user opaque containers until those
containers can carry their obligations. This includes receipts nested in records
or choices and retained through helper calls or fallible collection insertion.
Moving through a reference, including a field of a referenced record, must be
checked at the opaque ownership transition itself. Ordinary writes through opaque
slot pointers are subject to the same rule; lifetime summaries cannot substitute
for the missing completion protocol.
Possible cleanup on an error path does not certify completion on a path that
retains the receipt. Completed futures and tasks without borrowed inputs may
still be stored in collections. The model does not promise general
data-race freedom or exclusive mutable references. Helpers that start tasks may
have inferred nonaliasing preconditions: a local access can be valid when its
argument is disjoint from a task's loan, and invalid when those inputs alias.
These obligations propagate through wrappers and reference fields and are
checked at each caller. Completing the helper's own task before accessing the
referent removes that conflict. Erasure cannot hide an undeclared obligation.

Summarized may-access effects
are checked against entry authority before applying final completion guarantees.
Without an ordering proof, a helper that both completes a task and accesses its
loaned storage is conservatively rejected; completing in a separate earlier call
restores authority for subsequent calls. Unbounded erased calls still have a
known caller-side authorization gap; see the [design investigation](../plan/virtual_execution_safety.md#implementation-map-and-confirmed-gaps).
Atomic cells synchronize their own native operations without authorizing unrelated
value transfer.

Workers use an isolated callback signature, checked over all resolved reachable
bodies. They cannot access mutable module storage, module globals containing
references or owners, or unknown foreign, indirect or virtual targets. Immutable
plain globals remain available. The mutable-global restriction includes reads,
writes through helpers and effects of selected cleanup. Plain input and output
types alone do not establish isolation.

Raw context pointers and callback addresses establish no safe-reference validity
or lifetime facts. The bundled worker's trusted borrows are bounded by its
invocation: the native adapter owns correctly sized and aligned buffers until
the worker returns. Inputs permit only plain referents, and results prevent
borrowed leaves or destructors from escaping that boundary. A private
ingress operation reconstructs the checked nested reference facts for the worker.

## Access effects

Access requirements are separate from validity and final initialization state.
Reading a referent requires read authority; writing, consuming it or ending its
generation requires write authority. Writing an unchanged value still counts as
a write. Multiple mutable aliases within one sequential execution remain valid.

Effects propagate through ordinary calls using caller-relative input paths,
including references stored inside by-value records. Global access and selected
cleanup effects are transitive. Calls whose effects are not bounded, including
virtual calls with only lifetime contracts, retain unknown access effects;
an empty lifetime contract does not establish absence of memory access.

The compiler infers conservative may-access effects in safety summaries and
rejects mutable-global access from isolated callbacks. Task loans use the declared
reference capability, rather than narrowing authority to a worker's inferred
minimum effects. Virtual contracts can publish checked `reads`, `writes` and
`no_access` bounds for reference inputs, known field paths and mapped captured regions;
see [access bounds](134_virtual_types.md#access-bounds). Wrappers preserve receiver
and captured-region identities, including symbolic receiver references. Deeper
reference mappings, affinity and owning resource transfer remain open work. A bound on ordinary
memory accesses is neither a synchronization guarantee nor thread-transfer permission.

## Futures and executors

```rg
double := (.x: Int32) -> (.result: Int32) { result = x * 2 }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(double)(.args = (.x = 21)))
    result ::= unwrap_or_abort(.value = await($&future))
    if result != 42 { abort }
}
```

`async#(F)` uses the function's complete input record and produces a
`Future#(result_of#(F))`. Normal argument completion evaluates defaults and assumed
inputs in the caller. Use `prepare_args#(F)` when preparing the record separately.
`await` joins and copies out the result once; a second extraction returns
`already_awaited`. A function's own fallible result remains nested inside the
execution result. Zero and multiple outputs follow ordinary result conventions.

Future is move-only. Native stable buffers stay at the same addresses when the
Future moves. Dropping it joins before releasing those buffers, including when
the result was never awaited. A join failure retains native storage; explicit
await reports `task_join_failed`, while cleanup aborts rather than abandoning a
running worker. Launch or allocation failure reports `task_start_failed`.

Create a provider with `ThreadedExecutor(.ffi = system.ffi)` and explicitly
assume its virtual Executor handle. This initial backend creates one OS thread
per task. It has no worker pool, cancellation or task groups and currently runs
only in native execution.

Executor has one monomorphic submit operation. Its move-only TaskRequest binds the
callback, source borrow, sizes, alignments and a private execution receipt.
TaskReceipt owns native completion and cleanup. The submit contract requires
`carries_execution(result, request)` on success and
`completes_execution(request)` on failure; these checked guarantees survive
virtual dispatch. Forwarding providers move the request with `~request` rather
than duplicating it. A provider taking responsibility for a request must move it
into a lexical owner before a fallible start. Futures reject receipts for a
different typed worker with `executor_mismatch`. A foreign holder may invoke a callback repeatedly, so a
callback's reachable body cannot consume a `once` function.

A named access mapping to a `Virtual` field selects its erased receiver, while
reading the handle itself remains a separate access. Such a mapping does not
include the virtual's other named captured regions. The checker preserves this
distinction through delegation and functions returning virtual handles.

## Implementation boundary

Function identity parameters, signature queries, argument preparation and packed
invocation are implemented; see [compile-time computation](50_comptime.md).
Generic Runnable conformances can generate monomorphic virtual methods for task
specializations using ordinary language code.

The private native runtime provides joinable POSIX and Windows threads. Native
tests exercise a generated Argi callback on a worker, scalar argument/result
transport, joining, write publication, and rejection of destruction before join.
The native handle has one owner and its operations are serialized. Destruction
does not detach or implicitly join a thread. A failed join leaves the handle live.

Owning payloads and general cross-thread resource contracts are not yet
implemented. The next steps are recorded in
[the concurrency plan](../plan/concurrency.md).
