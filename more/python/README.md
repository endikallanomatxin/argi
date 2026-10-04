# Optional CPython embedding

See [the API and ownership contract](../../description/167_python.md). Ordinary
Argi builds do not require Python. Programs importing this module must compile
`runtime.c` with matching CPython development headers and explicitly link its
embedding library. CPython 3.12+ with the standard GIL is required.

## Preparing a consumer

Run the helper using the Python installation or virtual environment you want:

```sh
python3 more/python/build.py build path/to/module
python3 more/python/build.py run path/to/module --release
```

It discovers the matching development headers and shared embedding library,
compiles the adapter, and forwards ordinary build/run/test options to Argi with
explicit native dependencies. Python remains optional: the compiler itself has
no Python discovery or special package behavior. All options for the helper must
precede `build`, `run`, `test`, or `prepare`.

The prepared object is cached under `.argi-cache/native/python`, fingerprinted
by the adapter sources, headers, Python ABI/environment, driver, and arguments.
The helper compiles the selected Python executable as the default for
`Python(.ffi)`; an explicitly supplied non-default `.program_name` overrides it.
This also selects a virtual environment without setting global PYTHONHOME.

```sh
.venv/bin/python more/python/build.py --argi /path/to/argi build path/to/module
python3 more/python/build.py --cc gcc --cc-arg=-O3 build path/to/module
python3 more/python/build.py prepare
```

`prepare` prints a TOML fragment containing ordinary `[[native]]` file entries
for inclusion in a package manifest; `--json prepare` emits machine-readable
paths and driver flags. `--include-dir` (repeatable) and `--library` override
discovery for development installations. Missing headers/libraries produce
explicit setup diagnostics. The helper checks the header version; initialization
also checks the loaded embedding library against the compiled headers. Cache paths are absolute, so regenerate the fragment
when moving a package or its native environment.

The helper supports native GCC-compatible drivers, including Clang and MinGW.
Static Python embedding and cross builds require explicit target-native
compilation/linking; they are not automatically discovered from the host Python.
The installed helper lives at `lib/argi/more/python/build.py`.

## Manual compilation

On Linux with a shared CPython build and its development tools installed:

```sh
cc -std=c11 -O2 -fPIC $(python3-config --includes) -c more/python/runtime.c -o python_runtime.o
python_library=$(python3 -c 'import os, sysconfig; print(os.path.join(sysconfig.get_config_var("LIBDIR"), sysconfig.get_config_var("LDLIBRARY")))')
argi build tests/feature_tests/python/01_json --link-file python_runtime.o --link-file "$python_library"
```

Use the matching versioned `python3-config` and executable when several Python
installations coexist. For macOS or custom builds, obtain the embedding flags
with `python3-config --embed --ldflags` and declare their libraries using
`--link-library`/`--library-path`; driver-specific flags use repeatable
`--cc-arg`. An explicit library file is often simpler:

```sh
argi build path/to/module --link-file python_runtime.o --link-file /path/to/libpython3.14.so
```

Package manifests can declare these same dependencies using `[[native]]` file
entries for the object and the matching Python library. Paths are relative to
the package root. Compile the adapter again for each target and Python ABI;
Argi does not discover Python headers or add implicit native dependencies.
Installed distributions include the adapter source under `lib/argi/more/python`.
On Windows compile it with matching Python headers and link the Python import
library using the selected C driver; arrange DLL discovery at execution time.

The runtime still needs its Python standard library, installed packages, and
shared-library loader configuration. Linking libpython alone does not bundle a
Python environment. To use a virtual environment, initialize with its executable
path as `.program_name` and leave `.home` empty. Explicit `.home` is for selecting
an installation root, not a virtual environment. `PYTHONPATH` and site settings
retain their usual Python behavior.

`examples/numpy` copies an Argi numeric array into NumPy, calls an array method,
and copies the result back in bulk. Build it with the same native dependencies and
install NumPy in the selected Python environment first.

## Validation

Compile and run the native ownership/buffer probe with your Python flags:

```sh
cc -std=c11 -pthread $(python3-config --includes) tests/python_native.c \
  $(python3-config --embed --ldflags) -o python_native_test
./python_native_test
```

Executable compiler tests are optional unless their native dependencies are
provided; negative lifetime and copying tests always run. Set absolute paths:

```sh
ARGI_PYTHON_RUNTIME_OBJECT=/absolute/path/python_runtime.o \
ARGI_PYTHON_LIBRARY=/absolute/path/libpython3.14.so \
zig build test -j1 -Dtest-filter=python
```

The executable tests run outside the source checkout and repeat builds to
exercise frontend reuse. They cover JSON, positional/keyword calls, strict
conversions, integer boundaries, collections, binary NULs, traceback capture,
and recovery after failures. Method/iteration, recursive conversion, and retained
exception cases extend that coverage. The native probe checks reference counts, bounded
copies, initialization exclusion, finalization, rejected restart, and (on POSIX)
wrong-thread rejection.

For the complete native smoke (cached preparation, debug/release execution,
interpreter discovery, and installed-helper use):

```sh
python3 .github/scripts/python_smoke.py --argi zig-out/bin/argi --numpy
```

Pass `--include-dir` and `--library` when the selected installation needs explicit
headers or library paths. `--numpy` requires NumPy in that Python environment.

`numeric_buffer` exposes the same Python-owned copy without requiring NumPy.
`copy_numeric` accepts one-dimensional typed buffers, including strided inputs,
and checks type/width/byte order and capacity before writing initialized Argi
storage. For writable fixed-array destinations use
`array_view(.array = $&owner).view`. The API never lends an Argi allocation to Python's object graph.

The optional Python CI workflow exercises CPython 3.12 and 3.14 on Linux
x86_64/ARM64, macOS Intel/Apple Silicon, and Windows. It runs the native ownership
probe, debug/release consumers, NumPy, installed-helper preparation, and the
positive/negative compiler fixtures. Those dependencies belong to that workflow,
not to ordinary compiler builds.
