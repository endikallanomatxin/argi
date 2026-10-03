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
