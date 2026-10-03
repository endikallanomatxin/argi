# Native Windows support

## Direction

Port the compiler, installed CLI, and implemented core to native Windows x64
with one documented toolchain/CRT. Preserve language and safety contracts;
WSL is Linux support, not validation of this port.

## Work to do

- [ ] Establish a native runner and compatible Zig/LLVM development toolchain.
- [ ] Adapt LLVM discovery, linker arguments, ABI boundaries, and executable names.
- [ ] Add Windows page acquisition/release and matching aligned allocation/free.
- [ ] Adapt streams, filesystem, paths, arguments, and environment encoding.
- [ ] Make installation, LSP URIs, temporary paths, and test fixtures portable.
- [ ] Exercise compiler/core and installed projects natively; add Windows CI.

## Platform considerations

Current compiler/linker and core adapters assume Unix/POSIX in several places.
Windows page release needs the original reservation: `VirtualFree(MEM_RELEASE)`
releases it as a whole, unlike prefix/suffix unmapping. Keep any needed metadata
private and preserve allocation receipts and alignment guarantees.
See [VirtualFree](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualfree).

If using the CRT aligned allocator, pair `_aligned_malloc` with `_aligned_free`.
See [_aligned_malloc](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/aligned-malloc?view=msvc-170).

Use the first native build and allocation/I/O paths to reassess porting effort.
Multiple toolchains, Windows cross-linking, and new system services are separate
extensions; claim support only for the natively validated paths.
