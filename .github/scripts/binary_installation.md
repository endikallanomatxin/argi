# Argi binary distribution

This package includes the Argi compiler, core library, LLVM runtime, and
non-system runtime dependencies. Zig and a separate LLVM installation are
not needed. Keep `bin/` and `lib/` together when moving the package.

Add the extracted package's `bin` directory to `PATH`, then run:

```sh
argi --version
argi init hello
cd hello
argi run
```

Building Argi programs requires a system C compiler/linker and development
files for libc. On Ubuntu, install `build-essential`. On macOS, install the
Command Line Tools with `xcode-select --install`. Argi uses `cc` by default;
`CC=/path/to/compiler` selects another compiler.

Linux x86_64 and ARM64 (`aarch64`) packages are built on Ubuntu 24.04 and require glibc 2.39 or newer.
macOS packages are built on macOS 15, separately for Intel (`x86_64`) and
Apple Silicon (`aarch64`), and require macOS 15 or newer. These are native
distributions; cross-compilation is not included.

Verify the archive against the release's `SHA256SUMS` before extraction:

```sh
sha256sum --ignore-missing -c SHA256SUMS  # Linux
shasum -a 256 -c SHA256SUMS             # macOS, with all listed archives
```

The macOS binaries have ad-hoc signatures, not Apple notarization. If macOS
quarantines a browser download, review its origin and checksum before allowing
it through System Settings or removing the quarantine attribute from the
extracted directory with `xattr -dr com.apple.quarantine <directory>`.

`BUILD.json` records the source commit and native target. `LICENSE` covers
Argi; `licenses/` contains the notices for the bundled runtime libraries.
