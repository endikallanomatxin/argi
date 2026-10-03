# Native platform adapters

Private adapters use `#if target_os(...)` to select their declarations from
the compilation target. The compiler does not assign special meaning to their
folder names. Public `Memory`, `FileSystem`, and `Terminal` contracts remain
independent of these adapters; ordinary libraries can use the same selection
mechanism. Linux and macOS mapping flags are selected before compilation.

Page acquisition returns an aligned range and page release consumes that range.
POSIX can unmap alignment padding separately. Windows stores the original
`VirtualAlloc` reservation in a private header before the exposed range and
releases it as a whole with `VirtualFree`. The header is outside allocation
bounds and does not become initialized user storage.

The Windows C adapter is linked by the selected UCRT64 C driver from the
installed core. Its aligned allocator pairs `_aligned_malloc` with
`_aligned_free`; ordinary CRT `malloc` storage continues to use `free`.

Windows filesystem calls convert UTF-8 paths to UTF-16 within the native call
and release conversion buffers before returning. Terminal streams use binary
CRT mode so byte readers/writers do not translate newlines or treat Ctrl-Z as
end of file.

Argument and environment views use UTF-8 copies of Windows Unicode values.
Those bootstrap buffers remain valid until the generated entrypoint returns,
after language scope cleanup. Later environment queries retain earlier values
instead of replacing their storage. Console code pages are switched to UTF-8
only for console endpoints and restored at entry exit; redirected streams stay
ordinary byte streams.

Clock adapters return integral seconds and normalized nanosecond fractions.
POSIX bindings use the target's C `long` layout for `timespec`; Linux and macOS
select their native clock IDs. A failed `nanosleep` retries only `EINTR` with
its returned remainder. Long intervals use finite day-sized chunks to avoid
truncation by a kernel's signed nanosecond deadline representation. Its `errno`
pointer borrows the FFI capability as a root for live thread-local storage,
without claiming storage acquisition.

The Windows native adapter includes `time.c` after the Win32 declarations.
QPC ticks are converted with bounded integer division, avoiding both a wide
product and floating-point rounding. FILETIME values normalize negative Unix
seconds with a nonnegative fractional component. Sleep uses finite DWORD
chunks with upward rounding, then checks QPC again to handle early wakeups;
it never passes the `INFINITE` sentinel to the operating system.
