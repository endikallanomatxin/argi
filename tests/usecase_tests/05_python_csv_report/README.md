# CSV latency report with Python

This program summarizes request timings exported by a service. Argi reads the
file, checks duration values, owns the resources, and writes the report. Embedded
Python handles CSV quoting and multiline cells with `csv.DictReader`, then
calculates the mean and median with `statistics`. Only Python's standard library
is needed; there is no NumPy dependency or separate Python script.

Build the compiler, then use the Python adapter's preparation helper with the
Python installation you want to embed:

```sh
zig build
python3 more/python/build.py --argi ./zig-out/bin/argi build tests/usecase_tests/05_python_csv_report
./tests/usecase_tests/05_python_csv_report/build/output tests/usecase_tests/05_python_csv_report/requests.csv
```

CPython 3.12+ and matching development headers and an embedding library are
required. The helper discovers those dependencies; see
[Python setup](../../../more/python/README.md) for explicit paths and platform
instructions. Windows executables have the `.exe` suffix.

The supplied CSV includes a quoted comma, a multiline cell, and escaped quotes.
Its output is tab-separated:

```text
requests	4
mean_ms	40.00
median_ms	25.00
```

The second argument optionally selects a different duration column:

```sh
./tests/usecase_tests/05_python_csv_report/build/output timings.csv latency_ms
```

Durations are in milliseconds. Input is limited to 1 MiB and must be UTF-8.
At least one data row is required; missing columns, missing or nonnumeric cells,
negative durations, NaN, and infinity fail the program. Python exceptions are
printed to stderr before the interpreter is finalized. No report is written
until all rows and statistics have been checked. Output errors also propagate
through checked writes and a deferred flush.

The module alias `p` keeps Python calls compact. Python objects borrow their
interpreter and own their native references; automatic cleanup releases them
before finalization, including on errors. CSV text and sample values are copied
into Python-owned storage, with no shared Argi buffer.

The registered usecase test runs from a temporary working directory and checks
the sample, a custom column, empty data, conversion and validation errors, and
file/argument errors. It runs only when the optional native inputs are supplied:

```sh
ARGI_PYTHON_RUNTIME_OBJECT=/absolute/path/runtime.o \
ARGI_PYTHON_LIBRARY=/absolute/path/libpython.so \
zig build test -j1 -Dtest-filter=usecase_tests/05_python_csv_report
```
