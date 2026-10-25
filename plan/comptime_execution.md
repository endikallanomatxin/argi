# Execution follow-ups

- Record external compile-time reads as build dependencies before exposing those
  host capabilities. Define their reproducibility and cache identity.
- Separate host execution from target semantics for cross-compilation.
- Investigate continuation-state copying and session-layout rebuilding in growing
  live-binding sessions; compare with call-only workloads.
- Measure retained frame identities, aggregate backing and metadata before further
  reclamation; preserve dead identities, live references and cross-unit calls.
- Measure verifier join-state memory on real workloads before changing its
  representation. Use the execution benchmark and graph-pool statistics.
- Prepare raw/inherited resource storage when a concrete consumer requires it.

Frontend work: [incremental frontend](frontend_review.md).
Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).
