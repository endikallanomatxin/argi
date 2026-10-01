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
    .file_sys: $&FileSystem
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

> [!IMPLEMENTATION]
> `Network`, `ProcessManager`, `Clock`, and `RandomNumberGenerator` are
> currently capability placeholders without general operations.

Functions receive the capabilities they use through ordinary inputs. They
may be passed explicitly or supplied through lexical `assume` or a declared
`reach` input. There is no implicit default allocator. For example:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
}
```

The allocator created here belongs to `main`'s scope. Its reference may serve
calls in that scope, but cannot escape after the allocator is cleaned up.

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

For buffered output, borrow the terminal's file and select the buffer's
allocator explicitly. `BufferedWriter` defaults to a 4096-byte buffer; callers
may override `.capacity`. `print` flushes before returning, and callers using
`write_byte` directly should call `flush` to handle errors. Cleanup attempts a
best-effort flush and releases the buffer without deinitializing the base file.

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume writer ::= $&unwrap_or_abort(
        .value = BufferedWriter#(.base_type: File)(.base = $&system.terminal&.stdout),
    )
    print("Hello world\n")
}
```

Streams may be redirected to files or pipes. A stream implementing `Reader`
or `Writer` does not by itself promise terminal-specific operations such as
querying screen dimensions.
