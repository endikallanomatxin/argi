# Native Windows support

## Direction

Port the compiler, installed CLI, and implemented core to native Windows x64
with one documented toolchain/CRT. Preserve language and safety contracts;
WSL is Linux support, not validation of this port.

## Work to do

- [ ] Broaden Windows coverage to the compiler and core feature suites; make
  remaining Unix-specific fixtures portable and check library resolution.
- [ ] Document installation and exercise the installed CLI/LSP outside the repo.

## Library boundary

Keep `Memory`, `FileSystem`, and `Terminal` independent of their OS adapters.
Target predicates and `#if` select private implementations before dependency
discovery and tokenizing. This is static information, not another runtime
capability. Concentrate selection at adapter boundaries instead of scattering
OS checks throughout public core APIs. See the
[compile-time target model](../description/50_comptime.md#compilation-target).

## Platform considerations

Use one UCRT-based MinGW toolchain for Argi and generated programs. LLVM's C
API DLL may come from its official MSVC development distribution: the emitted
target must come from Argi's target identity rather than the DLL's build host.
Only supported X86 and AArch64 backends need initialization. The standalone
LLVM installer lacks most C API headers; use the development archive instead.

Windows page release needs the original reservation: `VirtualFree(MEM_RELEASE)`
releases it as a whole, unlike prefix/suffix unmapping. Keep any needed metadata
private and preserve allocation receipts and alignment guarantees.
See [VirtualFree](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualfree).

If using the CRT aligned allocator, pair `_aligned_malloc` with `_aligned_free`.
See [_aligned_malloc](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/aligned-malloc?view=msvc-170).

Use the first native build and allocation/I/O paths to reassess porting effort.
Multiple toolchains, Windows cross-linking, and new system services are separate
extensions; claim support only for the natively validated paths.
