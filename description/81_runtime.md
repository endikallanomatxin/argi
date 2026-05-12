# Runtime

The idea is inspired by Zig's `Io` approach, but in Argi we call it `Runtime`
because it is not only about input/output.

`Runtime` is the execution capability of the program. It controls:

- task scheduling
- light threads
- async/concurrent execution
- yielding
- cancellation checkpoints
- runtime-aware synchronization primitives
- blocking operations such as sleep, IO, channels, mutexes, waits, etc.

## Runtime as a capability

`Runtime` should probably be an `Abstract` capability:

```rg
Runtime : Abstract = (
    lazy       (.self: $&Self, .task: Task) -> (.task: Task)
    async      (.self: $&Self, .task: Task) -> (.future: Future)
    concurrent(.self: $&Self, .task: Task) -> !(.future: Future)

    await      (.self: $&Self, .future: $&Future) -> !()
    cancel     (.self: $&Self, .future: $&Future) -> ()

    yield      (.self: $&Self) -> ()
    checkpoint (.self: $&Self) -> !()

    sleep      (.self: $&Self, .duration: Duration) -> !()
)
```

Possible implementations:

```rg
SingleThreadRuntime
ThreadedRuntime
FiberRuntime
TestRuntime
DeterministicRuntime
```

The concrete runtime determines how tasks are executed:

- `SingleThreadRuntime`: simple, mostly synchronous, useful for minimal targets.
- `ThreadedRuntime`: uses OS threads.
- `FiberRuntime`: uses light threads/fibers multiplexed over OS threads.
- `TestRuntime`: deterministic runtime for tests, fake timers, fake IO, etc.

---

## Runtime and System

By default, `system.runtime` should be a `BlockingRuntime`.

```rg
System : Type = (
    .allocator : $&Allocator
    .terminal  : $&Terminal
    .file_sys  : $&FileSystem
    .network   : $&Network
    .clock     : $&Clock
    .threads   : $&ThreadCapability
    .runtime   : $&Runtime
)
````

The default runtime is intentionally boring:

```rg
BlockingRuntime : Type = (...)
```

It behaves as if there was no scheduler.

```text
BlockingRuntime:
    async       -> may run immediately
    concurrent  -> returns ConcurrencyUnavailable
    yield       -> no-op
    checkpoint  -> cancellation check or no-op
    sleep       -> blocking sleep
    await       -> returns already completed work or blocks
```

This means ordinary Argi programs can always receive a `Runtime`, but they do
not automatically get light threads, worker threads, event loops or parallelism.

The default runtime is only a compatibility capability. It gives functions a
uniform interface without forcing every program to initialize a real scheduler.

---

## Creating a real runtime

If a program wants real concurrency, it must explicitly create a concrete
runtime.

For example:

```rg
main(.system: System = System()) -> !(.status_code: Int32 = 0) := {
    runtime := FiberRuntime(
        .allocator = system.allocator,
        .threads = system.threads,
        .count = 4,
    )

    future := runtime | concurrent($&_, Task({
        do_work(.runtime = $&runtime)!
    }))!

    future | await($&_)!
}
```

Creating a real runtime is a side-effectful operation because it may allocate
memory, create OS threads, register timers, initialize queues, or set up IO
polling.

Therefore, real runtime construction should require the relevant `System`
capabilities.

Examples:

```text
ThreadedRuntime:
    needs allocator
    needs thread capability

FiberRuntime:
    needs allocator
    may need thread capability
    may need clock/timer capability

EventedRuntime:
    needs allocator
    needs OS event/polling capability
    may need network/file capabilities

TestRuntime:
    may need allocator
    usually does not need OS thread capability
```

So `Runtime` is not ambient power by itself. The power comes from the concrete
runtime implementation and the capabilities used to construct it.

---

## Reached runtime

Functions may still receive a runtime through `#reach`, but this does not imply
that they get real concurrency.

```rg
do_work(
    .runtime: $&Runtime = #reach runtime, system.runtime,
) -> !() := {
    runtime | checkpoint($&_)!
    ...
}
```

If the caller only has `system.runtime`, this resolves to the default
`BlockingRuntime`.

If the caller has created a real runtime and binds it locally, `#reach runtime`
will find the local runtime first:

```rg
main(.system: System = System()) -> !(.status_code: Int32 = 0) := {
    runtime := FiberRuntime(
        .allocator = system.allocator,
        .threads = system.threads,
        .count = 4,
    )

    do_work()
}
```

In this example, `do_work()` receives the local `FiberRuntime`, not
`system.runtime`.

This keeps the model explicit and ergonomic:

```text
No custom runtime created:
    functions use system.runtime -> BlockingRuntime

Custom runtime created locally:
    functions use local runtime through #reach

Runtime with OS threads:
    requires explicit thread capability from System
```


## Task, Future, async and concurrent

Argi should separate two different axes:

```text
lazy/eager       = when the work starts
async/concurrent = what progress guarantee is required
```

### Task

A `Task` is a value that describes work.

Creating a task does not start it.

```rg
task := Task({
    expensive_work()
})
```

A task can later be consumed in different ways:

```rg
result := task | run()

future := runtime | async($&_, task)

future := runtime | concurrent($&_, task)!
```

So the model is:

```text
Task                  = work description
Task.run              = execute synchronously now
Runtime.async         = start now, concurrency optional
Runtime.concurrent    = start now, concurrency required
```

### async

`async` starts work, but concurrent progress is only an optimization.

A runtime is allowed to execute the task immediately, defer it, or overlap it
with other work.

Use `async` when the program remains correct even if the task runs
synchronously.

```rg
load_config_task := Task({
    load_config()
})

future := runtime | async($&_, load_config_task)

do_other_setup()

config := future | await($&_)!
```

If the runtime executes `load_config()` immediately, the program is still
correct. It may only be less efficient.

### concurrent

`concurrent` starts work and requires concurrent progress.

If the runtime cannot guarantee that the task can progress concurrently, it
should fail.

```rg
producer := runtime | concurrent($&_, Task({
    produce($&channel)
}))!

consumer := runtime | concurrent($&_, Task({
    consume($&channel)
}))!

producer | await($&_)!
consumer | await($&_)!
```

Use `concurrent` when sequential execution could deadlock or be incorrect.

Examples:

- producer/consumer with bounded channels
- reading both stdout and stderr of a subprocess
- server accept loop plus connection handlers
- two tasks that must communicate while both are alive

---

## lazy

`lazy` should not mean “lazy async”. It should simply mean task construction.

The clean model is:

```rg
task := Task({
    work()
})
```

or, if we want runtime-created task values:

```rg
task := runtime | lazy($&_, {
    work()
})
```

But the first option is probably cleaner:

```text
Task    = normal value
Runtime = capability that executes tasks
```

Creating a `Task` should not count as a scheduling side-effect. Executing it
does.

---

## Future

A `Future` represents a running or completed task.

```rg
future := runtime | async($&_, Task({
    compute()
}))

result := future | await($&_)!
```

A `Future` should probably be non-copyable, because it represents ownership of a
running task result or task handle.

Possible operations:

```rg
Future#(.t: Type) : Type

await (.runtime: $&Runtime, .future: $&Future#(.t: t)) -> !(.value: t)
cancel(.runtime: $&Runtime, .future: $&Future) -> ()
```

---

## yield

`yield` is an explicit cooperative scheduling point.

It means:

```text
The current task is willing to let another ready task run.
```

It should not be modeled as `sleep(0)`. Sleeping is a timer operation. Yielding
is a scheduler operation.

Example:

```rg
heavy_cpu_task(
    .runtime: $&Runtime = #reach runtime, system.runtime,
) -> !() := {
    for i in Range(.start = 0, .end = huge_number) {
        do_step(i)

        if i % 1024 == 0 {
            runtime | yield($&_)
        }
    }
}
```

In a `FiberRuntime`, `yield` switches to another ready light thread.

In a `ThreadedRuntime`, `yield` may call the OS scheduler or be a cheap no-op.

---

## checkpoint

Most CPU-heavy code should call `checkpoint` instead of `yield`.

```rg
runtime | checkpoint($&_)!
```

`checkpoint` means:

```text
1. check whether the current task was cancelled
2. yield cooperatively if useful
3. return cancellation as an error if needed
```

Example:

```rg
parse_large_file(
    .runtime: $&Runtime = #reach runtime, system.runtime,
    .content: &String,
) -> !(.ast: Ast) := {
    for token in tokenize(content) {
        consume_token(token)

        if should_checkpoint() {
            runtime | checkpoint($&_)!
        }
    }
}
```

Rule of thumb:

```text
runtime.yield()      = only scheduling
runtime.checkpoint() = scheduling + cancellation
```

Most user code should prefer `checkpoint`.

---

## Light threads

A light thread is a runtime-managed task.

Light threads are not necessarily OS threads. They can be multiplexed over a
smaller number of OS threads.

The runtime is responsible for:

- multiplexing tasks over OS threads
- load balancing
- parking tasks that wait for IO, timers, channels or locks
- resuming tasks when their wait condition is satisfied
- cancellation
- coordination primitives such as channels and wait groups

Example:

```rg
runtime := FiberRuntime(.threads = 4)

future := runtime | concurrent($&_, Task({
    ...
}))!

future | await($&_)!
```

In the long term, `main` should run inside the root runtime task, so that main
itself can call `yield`, `checkpoint`, `sleep`, `await`, channels, etc.

```rg
main(.system: System = System()) -> !(.status_code: Int32 = 0) := {
    runtime : $&Runtime = system.runtime

    future := runtime | concurrent($&_, Task({
        serve(.runtime = runtime)
    }))!

    runtime | checkpoint($&_)!

    future | await($&_)!
}
```

---

## No async functions

Argi does not need async functions as a language feature.

Instead, ordinary functions can be executed as tasks by the runtime.

```rg
work() -> !() := {
    ...
}

future := runtime | async($&_, Task({
    work()!
}))
```

This fits better with stackful light threads/fibers:

```text
ordinary functions can yield
ordinary functions can wait
ordinary functions can call runtime-backed blocking operations
the compiler does not need to transform every async function into a state machine
```

---

## Capture rules for Task

Tasks must have strict capture rules.

A task may outlive the scope where it was created, so captures must be safe.

Recommended rules:

- owned values are moved into the task
- copied values require `copy()`
- read references require lifetime checking
- mutable references should be rejected unless the compiler proves the task
  cannot outlive the borrow
- shared mutable state should go through mutexes, channels, atomics or other
  runtime-safe primitives

Bad:

```rg
x := 0

task := Task({
    x += 1
})
```

Better:

```rg
state : Mutex#(.t: Int32)

task := Task({
    state | with_lock($&_, {
        state.value += 1
    })
})
```

For `concurrent`, the same thread-safety rules should apply as for OS threads:

A concurrent task should only receive:

- owned values
- read-only references
- exclusive values proven not to alias
- channels
- mutexes
- atomics
- other explicitly thread-safe handles

---

## Channels

Channels should be created from the runtime, because their blocking behavior
depends on the runtime.

A channel in a `ThreadedRuntime` may block an OS thread.

A channel in a `FiberRuntime` should park the current light thread and let
another task run.

```rg
channel := runtime | channel($&_, .t = Int32)
```

Possible channel families:

```rg
Channel#(.t: Type) : Abstract = (
    put(.self: $&Self, .value: t) -> !()
    get(.self: $&Self) -> !(.value: t)
)
```

Concrete implementations:

```rg
Spot#(.t: Type)
Queue#(.t: Type)
Stack#(.t: Type)
```

Meaning:

- `Spot`: one-seat channel, similar to an unbuffered/single-slot handoff.
- `Queue`: FIFO buffered channel.
- `Stack`: LIFO buffered channel.

Example:

```rg
channel := runtime | channel($&_, .t = Int32)

producer := runtime | concurrent($&_, Task({
    channel | put($&_, 42)!
}))!

consumer := runtime | concurrent($&_, Task({
    value := channel | get($&_)!
    print(value)
}))!

producer | await($&_)!
consumer | await($&_)!
```

Channel operations are side-effects and may suspend the current task.



---

Ejemplos / Código antiguo:

```
funcion_enviadora (c:Channel) -> () := {
	time | sleep (&_, 1000)
	c | send (_, 42)
}

canal : Channel#(.t: Int)

for i in Range(.start = 1, .end = 10) {
	lcr | spawn_thread ($&_, funcion_enviadora, (canal))
}

loop {
	print(canal|receive)
}
```


```
Channel#(.t: Type) : Abstract = (
    put(.self: $&Self, .value: t) -> ()
    get(.self: $&Self) -> (.value: t)
)
Spot implements Channel
Queue implements Channel
Stack implements Channel
Channel defaults Spot


Queue#(.t: Type) : Abstract = (
	put(.self: $&Self, .value: t) -> ()
	get(.self: $&Self) -> (.value: t)
)
DynamicQueue#(.t: Type) implements Queue#(.t: t)
StaticQueue#(.n: UIntNative, .t: Type) implements Queue#(.t: t)
Queue defaults DynamicQueue

Stack#(.t: Type) : Abstract = (
	put(.self: $&Self, .value: t) -> ()
	get(.self: $&Self) -> (.value: t)
)
DynamicStack#(.t: Type) implements Stack#(.t: t)
StaticStack#(.n: UIntNative, .t: Type) implements Stack#(.t: t)
Stack defaults DynamicStack

```

```
channel: Channel

channel|put("message")
print(channel|get)
```

```
a: Spot(Int)
branch {
	a|put funcion 1
}

b: Spot(Int)
branch {
	b|put funcion 2
}

c = a|get + b|get
```

---

## Mutex

Mutexes should also be runtime-aware.

The old idea was:

```rg
estado : Mutex#(.t: Int32)

incrementar($&estado) := {
    estado | lock($&_)
    estado.value += 1
    estado | unlock($&_)
}
```

But manual lock/unlock is error-prone.

Prefer scoped locking:

```rg
estado : Mutex#(.t: Int32)

incrementar(.estado: $&Mutex#(.t: Int32)) -> !() := {
    estado | with_lock($&_, {
        estado.value += 1
    })!
}
```

In a `ThreadedRuntime`, a mutex may block the OS thread.

In a `FiberRuntime`, a contended mutex should park the current light thread
instead of blocking the whole OS thread.

So mutexes should probably be created by the runtime:

```rg
estado := runtime | mutex($&_, .value = 0)
```


> [!IDEA] Automutex
> ```
> estado : AutoMutex<Int>
> 
> incrementar($&estado) := {
> 	estado++
> }
> 
> for i in Range(.start = 1, .end = 10) {
> 	spawn_thread({
> 		incrementar($&estado)
> 	})
> }
> ```


---

## RW Lock

RW locks are useful when many readers can access shared state while writers need
exclusive access.

```rg
state := runtime | rw_lock($&_, .value = initial_state)
```

Possible API:

```rg
state | with_read_lock($&_, {
    use_read_only(state.value)
})!

state | with_write_lock($&_, {
    mutate(state.value)
})!
```

Readers block writers, but not other readers.

Writers block both readers and other writers.

Like mutexes, RW locks should be runtime-aware.

> En una charla de zig sobre concurrencia
> (https://www.youtube.com/watch?v=x1N9JPPPC18&list=WL&index=3) dice que es
> mejor usar RW locks que mutexes, porque los lectores solo bloquean a los
> escritores, y no a otros lectores.

---

## Semaphores

Semaphores should also be runtime-aware.

```rg
sem := runtime | semaphore($&_, .permits = 4)

sem | acquire($&_)!
defer sem | release($&_)
```

Possible scoped version:

```rg
sem | with_permit($&_, {
    do_limited_work()
})!
```

Use semaphores to limit concurrency:

- maximum number of active requests
- maximum number of open files
- maximum number of parallel workers
- rate-limited sections

---

## Wait groups

Wait groups should be created from the runtime.

```rg
wg := runtime | wait_group($&_)
```

Possible API:

```rg
wg | go($&_, Task({
    ...
}))

wg | go($&_, Task({
    ...
}))

wg | wait($&_)!
```

`wg.go` should probably use `runtime.concurrent` internally, because wait groups
normally express work that is expected to progress concurrently.

Alternative explicit API:

```rg
future1 := runtime | concurrent($&_, Task({ ... }))!
future2 := runtime | concurrent($&_, Task({ ... }))!

wg | add($&_, future1)
wg | add($&_, future2)

wg | wait($&_)!
```

The first version is more ergonomic.

---

## branch

`branch` could be syntactic sugar for structured concurrency.

Example:

```rg
branch runtime {
    a := compute_a()
    b := compute_b()
}

c := a + b
```

Possible meaning:

```text
1. create a structured wait group
2. launch each branch as a concurrent task
3. wait at the end of the branch block
4. make results available after all branches finish
5. cancel sibling branches if one branch fails
```

Lowering idea:

```rg
wg := runtime | wait_group($&_)

future_a := wg | go($&_, Task({
    compute_a()
}))

future_b := wg | go($&_, Task({
    compute_b()
}))

wg | wait($&_)!

a := future_a | await($&_)!
b := future_b | await($&_)!
```

This fits better than unstructured goroutine-style spawning.

---

## Blocking operations

Any operation that may block should eventually go through `Runtime`.

Examples:

- sleep
- file read/write
- network accept/connect/read/write
- channel get/put
- mutex lock
- wait group wait
- process stdout/stderr reads
- subprocess wait

In a simple runtime, these operations may block the OS thread.

In a fiber runtime, they should suspend the current task and allow other tasks
to run.

This is the main reason to route these operations through `Runtime`.

---

## Relationship with System

`System` owns process capabilities.

`Runtime` owns execution semantics.

```text
System:
    allocator
    terminal
    file_sys
    network
    clock
    proc_man
    runtime

Runtime:
    tasks
    futures
    scheduler
    yield
    checkpoint
    cancellation
    runtime-aware synchronization
```

Filesystem, network and clock may remain separate capabilities, but operations
that can block should use `Runtime` internally or receive it as a reached
argument.

Example:

```rg
read_file(
    .file_sys: $&FileSystem = #reach file_sys, system.file_sys,
    .runtime: $&Runtime = #reach runtime, system.runtime,
    .path: String,
) -> !(.content: String) := {
    ...
}
```

---

## Implementation strategy

### Stage 1: ThreadedRuntime

Start with an OS-thread-based runtime.

```text
Task          = boxed function + captures
Future        = handle + result storage
async         = may run inline or submit to worker pool
concurrent    = submit to OS thread / worker pool, may fail
await         = wait/join
yield         = OS scheduler yield or no-op
checkpoint    = cancellation check + yield
sleep         = blocking sleep
```

This gives the API shape without requiring fibers immediately.

### Stage 2: FiberRuntime

Add stackful light threads.

```text
Task          = fiber + stack + state
yield         = save current fiber and switch to another ready task
checkpoint    = cancellation check + yield
sleep         = park task until timer fires
channel get   = park task until value is available
mutex lock    = park task until lock is available
```

This avoids needing async functions in the language.

### Stage 3: Runtime-backed IO

Move blocking IO operations onto the runtime.

Possible backends:

- blocking calls on worker threads
- non-blocking sockets with epoll/kqueue
- io_uring on Linux
- platform-specific async APIs
- deterministic fake IO for tests

The user-facing API should not depend on the backend.

---

## Rule of thumb

```text
Pure computation:
    no Runtime needed.

CPU-heavy computation inside a runtime task:
    call runtime.checkpoint() periodically.

Work description:
    Task({ ... })

Independent work where concurrency is only an optimization:
    runtime.async(task)

Work that must progress concurrently:
    runtime.concurrent(task)!

Waiting for a running task:
    future.await()

Blocking external effects:
    go through System capabilities backed by Runtime.

Shared mutable state:
    use runtime-aware mutexes, RW locks, channels or atomics.
```

---

## Open questions

- Should `Task({...})` be syntax sugar or a normal core type?
- Should `lazy` exist as a runtime method, or should task construction be only
  `Task({...})`?
- Should `async` be infallible and `concurrent` errable?
- Should `yield` be infallible?
- Should `checkpoint` be the only cancellation point for CPU-heavy tasks?
- Should channels/mutexes be created only from `Runtime`?
- Should `branch` be the preferred syntax for structured concurrency?
- Should unstructured `concurrent` spawning be discouraged outside low-level
  code?
- Should `main` always receive `System`, and therefore `system.runtime`, by
  default?


---
---

>[!QUESTION]
>Lo único que no habría que permitir closures, porque no está claro como se va
>a comportar no?

Tiene sentido no permitir que el input no sean deep_copies o mutex o channels?
La mutabilidad como se gestiona?

>[!ERROR]
>En go las goroutines no puedes return. Eso es una asyn func.
>Igual la clave es encontrar una sintaxis que me permita hacer algo similar de
>forma sencilla.


