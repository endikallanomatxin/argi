# System

An executable may declare `main(.system: System)`. The program entry scope
creates the process resources, passes references to them through `System`, and
cleans them up after `main` returns. A `main` that needs none of these
capabilities may omit the input.

`System` is a bundle of capabilities, not an allocator or an owner of the
process resources. Copying it copies references to those resources; the
copies remain subject to their lifetimes.

```rg
System : Type = (
    .memory: $&Memory
    .page_allocator: $&PageAllocator
    .terminal: $&Terminal
    .args: $&Arguments
    .env_vars: $&EnvironmentVariables
    .file_system: $&FileSystem
    .network: $&Network
    .proc_man: $&ProcessManager
    .clock: $&Clock
    .rand_gen: $&RandomNumberGenerator
    .ffi: $&ForeignFunctionInterface
)
```

The fields expose different kinds of work: memory and allocation, terminal
I/O, process arguments and environment, files, networking, processes, time,
randomness, and foreign calls.

`Network` provides [blocking address resolution, TCP, and UDP](168_networking.md).

`RandomNumberGenerator` provides [system entropy](163_randomness.md).
`Clock` provides [monotonic time, civil time, and blocking sleep](164_time.md).
`ProcessManager` provides [child processes and their streams](165_processes.md).

Functions receive the capabilities they use through ordinary inputs. They
may be passed explicitly or supplied through lexical `assume` or a declared
`reach` input. There is no implicit default allocator. For example:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
}
```

The allocator created here belongs to `main`'s scope. Its reference may serve
calls in that scope, but cannot escape after the allocator is cleaned up.

## Program results

`main` may return one `.status_code: Int32` output or one `.result` containing
an `Errable<Void>`. The fallible shorthand infers its reasons:

```rg
main(.system: System) -> !Void = ..ok Void() := {
    write(.self = $&system.terminal&.stdout, .text = "ready\n")!
}
```

The explicit default makes successful completion return `..ok Void()` without
assigning `result` in the body. It is an ordinary output default, not an
implicit return of the last expression. The same contract works without a
`System` input and with the explicit `Errable#(.t: Void)` output form.

Success exits with status `0`. A returned error exits with status `1` and
writes an unhandled-error heading followed by its trace to stderr. Reporting
calls the `ErrorTracer` retained by that error through its ordinary interface.
The default entry tracer retains bounded context in a 4096-byte stack buffer;
its report marks context truncation when needed. A program may supply another
tracer provided its lifetime covers the returned error and reporting.

Reporting runs before entry-owned terminal, tracer, and other process
resources are cleaned up. Reporting failures do not recursively report or
change the failure exit status. The integer-returning contract continues to
use the program's explicit status code.

## Stream capabilities

`System.terminal` groups the process streams as `stdin`, `stdout`, and
`stderr`, each a `File` value. Terminal initializes and cleans up these files
in the checked program entry scope; it does not select a buffering policy or
allocate buffers.

I/O helpers name their dependencies `reader` for reading and `writer` for
writing. These names describe the operation rather than a process-specific
stream. A writer may be a file, buffered writer, or another implementation of
`Writer`. Error-reporting helpers also take a writer; route them explicitly to
`system.terminal&.stderr` or select that writer in a nested lexical scope.

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume reader ::= $&system.terminal&.stdin
    assume writer ::= $&system.terminal&.stdout
    print("Hello world\n")
    print_error(.value = "A diagnostic\n", .writer = $&system.terminal&.stderr)
}
```

For buffered output, borrow the terminal's file and supply a view over an
initialized byte buffer. Construction is infallible and does not allocate;
the caller selects local storage, allocated storage, or a reusable buffer.
`zeroed` constructs numeric zeros, null C callbacks, and fixed arrays of those
values.
It does not construct references or arbitrary resource-bearing types.
`view($&array)` creates a writable view; `view(&array)` creates a read-only
view. Both retain the backing array's validity dependencies.

`print` flushes before returning. Callers using `write_byte` directly should
call `flush` to handle errors. Cleanup attempts a best-effort flush and leaves
both the buffer and base writer alive. An empty buffer forwards writes directly
to the base writer. Both borrowed resources must outlive the wrapper; temporaries
referenced in the `assume` expression remain alive for its enclosing scope.

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout,
        .buffer = view($&zeroed#(.t: [4096]UInt8)()),
    )
    print("Hello world\n")
}
```

Streams may be redirected to files or pipes. A stream implementing `Reader`
or `Writer` does not by itself promise terminal-specific operations such as
querying screen dimensions.

A fallible `main` may create a fixed-size tracer, its backing array, and its
virtual interface locally. Returning an error retains that bounded storage
in the entry wrapper, which reports the trace before running its cleanup.
The error's existing tracer interface controls reporting; the wrapper does
not replace it with the default tracer.
