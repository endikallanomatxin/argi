# Execution follow-ups

Release: [0.4](0.4.md). Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).

## Compile-time host

- Extend `System` entries to generic templates through the existing staged
  materialization path; preserve compile-time captures and branch selection.
- Audit host-entry rollback and repeated evaluation in persistent sessions.
- Keep external reads disabled until their build dependencies are recorded.
  The initial host policy provides empty arguments, stdout/stderr and VM allocation.

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
