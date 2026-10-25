# Execution follow-ups

Release: [0.4](0.4.md). Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).

## Compile-time host

- Keep external reads disabled until their build dependencies are recorded.
  The initial host policy provides empty arguments, stdout/stderr and VM allocation.

## Later

- Prepare raw/inherited resource storage explicitly when a concrete consumer needs it.
- Separate host execution from target semantics for cross-compilation.

- Measure retained frame identities, aggregate backing and metadata before further
  reclamation. Call value/cleanup buffers already reuse exact-size bins; preserve
  dead identities, live references and cross-unit calls.
- Measure verifier join-state memory on real workloads before changing representation.
  Use the existing session benchmarks and graph-pool statistics.

Frontend investigations: [frontend review](frontend_review.md).
