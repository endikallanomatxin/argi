# Processes

`ProcessManager` is the capability for launching child processes. It borrows
`ForeignFunctionInterface`; `System.proc_man` provides the entry scope's manager.
`spawn` accepts it as `.self: &ProcessManager = reach proc_man`.

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume proc_man ::= system.proc_man
    args: [1]StringView = ("--version")
    child ::= unwrap_or_abort(.value = spawn(
        .executable = "argi",
        .arguments = view(.array = &args),
    )).result
    status ::= unwrap_or_abort(.value = wait(.self = $&child)).result
    match status {
        ..exited value {
            if value.code != 0 { status_code = 1 }
        }
        ..signaled _ { status_code = 1 }
    }
}
```

## Launch

`spawn(.executable: StringView, .arguments: ArrayViewRO#(.t: StringView),
.stdin: ProcessStreamMode, .stdout: ProcessStreamMode,
.stderr: ProcessStreamMode, .self: &ProcessManager)` returns
`Errable<Process>` with `invalid_process_argument`, `out_of_memory`, or
`process_spawn_failed`.

Arguments default to an empty view and exclude the executable's own argument.
Each stream defaults to `..inherit`. `ProcessStreamMode` also provides `..pipe`
and `..discard`. The executable is nonempty; every input string must be valid
UTF-8 without embedded NUL bytes. Empty arguments are preserved. Temporary
native launch storage copies the strings before creating the child and is
released before `spawn` returns, including failure paths. No Argi allocator is
required and the returned process does not borrow argument storage.

Launch uses native executable lookup and inherits the parent's environment and
working directory. There is no shell expansion, command-string evaluation,
or interpretation of spaces or metacharacters. On Windows, arguments are
encoded as UTF-16 using the Windows CRT argv convention. Programs that decode
the raw command line using other conventions require their own adaptation.
Platform launch limits remain applicable; failures to launch return errors
rather than a fabricated child status.

## Streams

`Process` owns `.stdin`, `.stdout`, and `.stderr`, each a `ProcessStream`.
A requested pipe creates a parent endpoint: stdin is writable, stdout and
stderr are readable. Inherited and discarded streams expose no parent endpoint.
`is_open` reports whether an endpoint is present. The child sees EOF from a
discarded input; discarded output goes to the platform null device.

`ProcessStream` implements `Reader` and `Writer`. Operations on a closed
endpoint or in the wrong direction return the existing stream error reasons.
An open writable endpoint is unbuffered, so `flush` succeeds without additional
work. A broken pipe returns `stream_write_failed`. A read returning EOF produces
`..end`. `close` relinquishes the endpoint and can be repeated; it returns
`Errable<Void, stream_close_failed>`. Closing stdin supplies EOF to the child.

Streams borrow their containing process's lifetime. They are owners and cannot
be copied implicitly. Automatic process cleanup closes its endpoints; ordinary
safety rules reject using a borrowed stream after its process ends.

Operations are synchronous and may block. Pipe capacity is finite: drain output
before waiting when a child could fill a pipe. Programs needing simultaneous
bidirectional traffic must arrange appropriate scheduling; `wait` does not
collect output or implicitly close stdin. This API does not provide asynchronous
communication or an unbounded capture buffer.

## Wait, termination, and cleanup

`wait(.self: $&Process)` blocks until the direct child ends and returns
`Errable<ProcessExitStatus, process_wait_failed>`. `ProcessExitStatus` is an
implicitly copyable choice:

- `..exited(.code: UInt32)` is a normal exit, including a nonzero program status.
- `..signaled(.signal: UInt32)` is POSIX termination by signal.

Windows exit codes preserve all 32 bits and use `..exited`. POSIX normal exit
codes are the native low eight bits. Successful wait results are cached:
repeated waits produce the same result while leaving the pipes available for
reading any remaining bytes. A child program's unsuccessful exit is an ordinary
status, not a failure of `wait`.

`terminate(.self: $&Process)` returns
`Errable<Void, process_terminate_failed>` and requests forced termination of the
direct child: `SIGKILL` on POSIX, `TerminateProcess` with exit code 1 on Windows.
It succeeds if the child has already ended. It does not wait or terminate
other processes launched by that child. Call `wait` to obtain its final status.

`Process` cannot be copied implicitly or constructed from a native handle by
an external module. Its destructor closes pipe endpoints, forcibly terminates
a still-running child, waits for its release, and frees the native record.
Automatic cleanup may therefore block. Explicit destruction follows the same
contract. There is no detached-child ownership mode. Cleanup cannot return an
error; use explicit stream closure, termination, and wait when failures need to
be observed. External native code must not reap or close resources owned by an
Argi process; an externally reaped POSIX child causes `process_wait_failed` and
its old identifier is never signaled during cleanup.
