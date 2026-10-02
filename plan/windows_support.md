# Native Windows support

## Purpose and release scope

Target native Windows x64 support as a candidate milestone for [0.3](0.3.md).
Port the compiler, installed CLI, and implemented core library while preserving
the existing language and safety contracts. WSL execution is Linux support and
does not validate this milestone.

Start with one documented toolchain and ABI. Supporting multiple Windows
toolchains, cross-compilation, and new process/network/concurrency services are
separate milestones. This work does not delay the Linux/macOS 0.2 release.

## Initial findings

The compiler uses Zig and LLVM, but its build and linker integration currently
assume Unix-style library discovery and a `cc` invocation with `-lc`.
The page allocator uses POSIX mapping hooks; the Windows platform module is
empty. Core also relies on C runtime functions that need platform adaptation.
The test harness contains Unix temporary paths, shell fixtures, executable
names, and signal expectations. Existing CI validates Linux and macOS only.

The main design-sensitive boundary is aligned page allocation.
`Memory.rg` currently overmaps and unmaps unused prefix/suffix regions.
Windows `VirtualFree` with `MEM_RELEASE` requires the original reservation
address and a zero size, releasing the complete reservation. A Windows backend
therefore needs its own alignment strategy and, if necessary, private metadata
for the original reservation. Preserve the public `Allocation` contract,
physical acquisition receipts, and matching deallocation obligations.
See [VirtualFree](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualfree).

If the Microsoft CRT aligned allocator is used, `_aligned_malloc` must pair
with `_aligned_free`, rather than `free`. Adapt the allocation/free pair and
its signatures together, rather than only changing symbol aliases.
See [_aligned_malloc](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/aligned-malloc?view=msvc-170).

These findings come from code inspection; native Windows execution remains
unvalidated. The expected changes belong at platform and ABI boundaries, but
the first working build must confirm that assumption.

## Implementation order

- [ ] Select and document a Windows x64 toolchain, CRT, and LLVM 21 development
  library distribution compatible with Zig 0.16.x. Establish a native Windows
  runner for reproducible build and execution checks.
- [ ] Build the compiler on Windows. Adapt LLVM discovery and library linking
  without breaking the existing Linux/macOS configuration.
- [ ] Generate, link, and execute a minimal program. Adapt linker arguments,
  object/executable naming, and required system libraries; verify foreign-call
  signatures against the selected ABI.
- [ ] Implement Windows page acquisition and release. Cover page size versus
  allocation granularity, large alignments, overflow, allocation failure,
  reservation cleanup, and physical storage validity. Exercise PageAllocator,
  GeneralPurposeAllocator, Arena, and capability-based error tracing.
- [ ] Adapt C runtime allocation, standard streams, and filesystem operations.
  Define text/binary behavior and the path/argument/environment encoding
  boundary, including Unicode filenames. Keep capabilities explicit.
- [ ] Audit CLI installation, artifact replacement, path handling, and LSP
  file URIs for drive letters and Windows separators.
- [ ] Make temporary directories, executable paths, linker fixtures, and
  abnormal-exit assertions portable in the test harness.
- [ ] Run internal and feature tests natively, in development and release
  configurations where relevant. Add Windows CI and document the validated
  host/toolchain combination and any remaining limitations.

## Acceptance and scope review

First validate compiler build, minimal program execution, aligned allocation
and cleanup, terminal/file I/O, and an installed `argi init` project. Use that
checkpoint to reassess remaining effort before treating Windows as a 0.3
release gate.

Claim support only after native CI covers the supported compiler/library paths
and installation workflow. Fix platform differences without weakening safety
checks or silently reducing existing contracts. If the port exposes broader
language or ABI design work, record that separately and revisit the release
scope rather than expanding this milestone indefinitely.
