# Execution follow-ups

Release: [0.4](0.4.md). Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).

## Compile-time host

- Implement `#run (.system: System)` using the existing execution host boundary.
  Define permitted host effects and build dependencies before enabling external I/O.
  Use checked caller-owned resource storage: `system/68` proves initialization
  and `system/69X` rejects escaping its lifetime. Keep user assumptions inside
  the entry; resource construction must not install them in its lexical scope.
  Verify once acquisitions separately for each compile-time invocation. The
  evaluator currently rejects once/foreign bodies and nonconstant inputs, so
  enabling System requires an explicit host-entry path, not relaxing all entries.

## Later

- Prepare raw/inherited resource storage explicitly when a concrete consumer needs it.
- Separate host execution from target semantics for cross-compilation.

- Measure retained frames and metadata before introducing reclamation; preserve
  live references and cross-unit calls.
- Measure verifier join-state memory on real workloads before changing representation.
  Use the existing session benchmarks and graph-pool statistics.

Frontend investigations after the merge: [frontend review](frontend_review.md).

## Validation

- Pair each fix with native/VM coverage and persistent REPL cases where relevant.
  Include rejection, early exit, cleanup and reset, rather than only successful values.
- Confirm the final branch in Linux/macOS CI on x86_64/ARM64.
