# Developing Argi

The compiler is written in Zig and uses LLVM. Development targets `develop`;
`main` and version tags identify published releases.

## Building from source

Building the compiler requires Zig 0.16.x and LLVM 21 development files:

```sh
zig build                    # local installation in zig-out/
zig build -p ~/.local        # user installation, including core and more
export PATH="$HOME/.local/bin:$PATH"
```

LLVM is located through `llvm-config-21` or `llvm-config`; override paths with
`LLVM_INCLUDE_DIR`, `LLVM_LIB_DIR`, and `LLVM_LIBS` when needed.

See the [usage guide](docs/usage.md) for C linker selection and Argi installation
paths, or the [Windows guide](.github/scripts/windows_development.md) for
platform-specific setup.

## Compiler tests

Run the compiler's regression suite with:

```sh
zig build test -j16 -Dtest-jobs=16 --summary all
```

Program tests automatically use the available CPU count, capped at 16 worker
processes. `-Dtest-jobs=N` selects another count; the build job limit (`-jN`)
controls how many workers may run concurrently. For example, use
`zig build test -j16 -Dtest-jobs=16` to request 16 concurrent workers.
Installation and tests that touch shared state finish before the fixture workers
start. Parallel tests of the same fixture run on one worker. Compiler unit tests retain
Zig's standard runner.

Use `-Dtest-jobs=1 -j1` for the standard serial test runner, especially when
investigating compiler memory growth. `-Dtest-filter=contracts/` limits cases to
that name fragment, and `-Dtest-progress=true` records active case names in
`.zig-cache/program-tests/serial.log` and `worker-N.log`. These logs update while
cases run, and each worker writes its totals there when finished. Terminal
progress also shows active cases. With the standard serial runner, progress
prints each case directly. Avoid overlapping separate build invocations that
reinstall the bundled libraries.

For large fixture runs, use an optimized compiler while retaining Debug unit tests:

```sh
zig build test-internal -j16 -Dtest-jobs=16
zig build test-programs -Doptimize=ReleaseSafe -j16 -Dtest-jobs=16
```

Finish each build/test invocation before starting the next. Builds reinstall core
and more, so overlapping invocations can temporarily remove installed files.
Rebuild after changing either library before invoking `zig-out/bin/argi` manually.

If Zig selects an unwritable cache, set `ZIG_LOCAL_CACHE_DIR` and
`ZIG_GLOBAL_CACHE_DIR` to writable directories, such as `.zig-cache` and
`.zig-global-cache` under the checkout.

## Finding your way around

- `src/`: compiler and CLI, from tokenizing through code generation.
- `core/` and `more/`: foundational and domain-oriented libraries.
- `tests/feature_tests/`: focused language and library fixtures.
- `tests/usecase_tests/`: application examples and integration tests.
- `description/`: language design and supported behavior.
- `plan/`: remaining work and release priorities.

See [AGENTS.md](AGENTS.md) for repository conventions and the release workflow.
Frontend measurement and worker controls are documented in the
[performance guide](docs/compiler-performance.md). Language-level tests written
in Argi are covered in the [testing documentation](description/72_testing.md).
