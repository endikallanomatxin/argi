# Optional CPython embedding

See [the API and ownership contract](../../description/167_python.md). Ordinary
Argi builds do not require Python. Programs importing this module must compile
`runtime.c` with matching CPython development headers and explicitly link its
embedding library. CPython 3.12+ with the standard GIL is required.

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

`examples/numpy` calls `numpy.arange`, converts the array with `tolist`, and
reads its elements from Argi. Build it with the same native dependencies and
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
and recovery after failures. The native probe checks reference counts, bounded
copies, initialization exclusion, finalization, rejected restart, and (on POSIX)
wrong-thread rejection.
