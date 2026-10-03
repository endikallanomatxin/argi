# Windows x64 source builds

Use Windows 10/11 x64, Zig 0.16.x, LLVM 21, and the MSYS2 UCRT64 GCC toolchain.
Windows cross-linking and MSVC-based Argi builds are separate extensions.

1. Install [Zig 0.16](https://ziglang.org/download/) and
   [MSYS2](https://www.msys2.org/). In a UCRT64 shell, install the C driver:
   `pacman -S mingw-w64-ucrt-x86_64-gcc`.
2. Extract the `clang+llvm-21.1.8-x86_64-pc-windows-msvc.tar.xz` development
   archive from the [LLVM 21 release](https://github.com/llvm/llvm-project/releases/tag/llvmorg-21.1.8).
   The smaller installer lacks most development headers.
3. In PowerShell, point Zig at the extracted development files:

   ```powershell
   $llvm = 'C:/tools/clang+llvm-21.1.8-x86_64-pc-windows-msvc'
   $env:LLVM_INCLUDE_DIR = "$llvm/include"
   $env:LLVM_LIB_DIR = "$llvm/lib"
   $env:LLVM_LIBS = 'LLVM-C.lib'
   zig build -j1
   Copy-Item "$llvm/bin/LLVM-C.dll" 'zig-out/bin/'
   ```

Add `zig-out/bin` and MSYS2's `ucrt64/bin` to PATH, then use `argi init`,
`argi build`, `argi run`, and `argi lsp` normally. Argi uses `gcc` on Windows;
`CC` or `--cc` can select a compatible driver. Generated executables use the
UCRT64 ABI even though LLVM's C API DLL was built with MSVC.

For a separate installation, use `zig build -p C:/tools/argi` and copy the DLL
into that installation's `bin` directory. Keep `bin` and `lib/argi/core`
together: core includes the private Windows C adapter needed by the C linker.
Run `python .github/scripts/smoke_windows.py C:/tools/argi` to check the installed
compiler outside the checkout, including a path containing spaces and Unicode.

Native validation is defined in
[windows.yml](../workflows/windows.yml). This source-build workflow does not
publish Windows release binaries.
