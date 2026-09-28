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
