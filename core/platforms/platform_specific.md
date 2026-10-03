# Native platform adapters

Bundled core selects `platforms/windows/` or `platforms/posix/` from the
compilation target. These private adapters implement existing capabilities;
user modules keep ordinary folder namespaces.

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
