# Echo until an empty line

Build with `zig build`, then
`./zig-out/bin/argi build tests/usecase_tests/02_echo_until_empty`.
Run `tests/usecase_tests/02_echo_until_empty/build/output` (add `.exe` on Windows).

Each nonempty input line is echoed with a trailing LF. An empty line or EOF ends
the program; a final nonempty line without LF is also echoed. Each response is
flushed before reading the next line, so the example works interactively as well
as with redirected input. Line storage grows as needed rather than imposing a
fixed buffer limit.

The example uses an Errable entry point, assumed allocator and stream inputs,
and a single match after checked `read_line`. Each returned String is a scoped
owner; its borrowed text view is used before cleanup. A checked deferred flush
covers every scope exit. Input, allocation, write and flush errors produce a
failing exit status.
