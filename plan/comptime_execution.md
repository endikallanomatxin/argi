# Execution follow-ups

Release: [0.4](0.4.md). Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).

## Correctness

- Fix historical-alias invalidation after replacement through a retargeted
  reference field, including projections of references returned by wrappers.
- Audit native bulk copies of reference aggregates for companion evidence.

## Compile-time host

- Implement `#run (.system: System)` using the existing execution host boundary.
  Define permitted host effects and build dependencies before enabling external I/O.

## Later

- Prepare raw/inherited resource storage explicitly when a concrete consumer needs it.
- Separate host execution from target semantics for cross-compilation.

- Measure retained frames and metadata before introducing reclamation; preserve
  live references and cross-unit calls.
- Measure verifier join-state memory on real workloads before changing representation.
  Use the existing session benchmarks and graph-pool statistics.

## Validation

- Pair each fix with native/VM coverage and persistent REPL cases where relevant.
  Include rejection, early exit, cleanup and reset, rather than only successful values.
- Confirm the final branch in Linux/macOS CI on x86_64/ARM64.
