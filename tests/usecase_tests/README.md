# Application usecases

These small programs are executable examples and end-to-end compiler workloads:

- `01_cat`: binary streaming, CLI parsing, file ownership and error cleanup.
- `02_echo_until_empty`: growing line storage and interactive flushing.
- `03_word_count`: UTF-8, files, owning hash maps and deterministic result checks.
- `04_tree`: CLI schemas, bounded directory traversal and path ownership.
- `05_python_csv_report`: optional CPython integration; requires external setup.
- `06_weighted_regression`: rectangular and diagonal matrix products,
  transposition and static shape selection through `math/linear_algebra`.

The release smoke test copies the five dependency-free examples outside the
checkout, checks and compiles them using only the installed distribution, and
exercises debug/release outputs and selected failure paths. It supplies its own
small inputs and normalizes unordered output. Python remains independently
validated by the optional embedding workflow.

Run the same checks against a local installation:

```sh
python3 .github/scripts/smoke_release.py zig-out --usecases tests/usecase_tests
```

Use these directories for repeatable compilation measurements, recording build
mode, caching and frontend worker count. Source collection, frontend, LLVM and
linking are distinct costs. These correctness inputs do not establish runtime
throughput; benchmark larger observable workloads separately.
