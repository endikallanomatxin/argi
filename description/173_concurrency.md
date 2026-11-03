# Concurrency

The current interface is an initial restricted implementation. Access authority,
execution effects and general resource transfer are under design in
[the concurrency proposal](../plan/concurrency.md); they are not guarantees of
the implementation described here.

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

Borrowed references require both a live backing owner until completion and an
explicit permission to use the referent on another thread. Reference mutability
alone establishes neither permission nor synchronization. The model does not
promise general data-race freedom or exclusive mutable references. Atomic cells
can synchronize native operations without authorizing unrelated value transfer.

The worker owns task inputs while running. The caller cannot free task storage
until completion, including when it drops or moves the associated Future.
Completion must publish output initialization before the caller extracts the
result. A failed start must preserve cleanup of prepared inputs. A failed join
must preserve the running task's storage obligation.

The first backend accepts only plain values: recursively reference-free data
without selected destructors, raw pointer handles, virtual handles or callbacks.
`is_plain_data(.type = T)` reports this conservative type property; it grants no
ownership permission. Unsupported input or result types return
`unsupported_task_value` before a worker is created. Prepared owning inputs still
receive ordinary cleanup on that path. Transferring owners and borrowed values
requires further transfer evidence and storage accounting.

Workers use an isolated callback signature, checked over all resolved reachable
bodies. They cannot access module globals containing references or owners, or
call unknown foreign, indirect or virtual targets. Plain numeric globals remain
available; the caller must synchronize their concurrent access. An ordinary
function's plain input and output types alone would not bound its global loans.

Raw context pointers and callback addresses establish no safe-reference validity
or lifetime facts. The bundled worker's trusted borrows are bounded by its
invocation: the native adapter owns correctly sized and aligned buffers until
the worker returns, and the plain-value restriction prevents borrowed leaves or
destructors from escaping that boundary.

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

Executor has one monomorphic submit operation. Its opaque TaskRequest binds the
callback, source borrow, sizes and alignments; their private fields cannot be
altered by forwarding providers. TaskReceipt owns native completion and cleanup.
Forwarding executors must preserve the request and obey the declared storage
effects. Futures reject receipts for a different typed worker with
`executor_mismatch`. A foreign holder may invoke a callback repeatedly, so a
callback's reachable body cannot consume a `once` function.

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

General cross-thread transfer contracts for owners and references are not yet
implemented. The next steps are recorded in
[the concurrency plan](../plan/concurrency.md).
