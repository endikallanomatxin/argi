# Execution follow-ups

- Record external compile-time reads as build dependencies before exposing those
  host capabilities. Define their reproducibility and cache identity.
- Separate host execution from target semantics for cross-compilation.
- Investigate unused immutable aggregate payloads. Reclamation must preserve
  external invocation results, cross-frame writes, session/acquired publication
  and virtual descriptors; a live-frame walk alone is not a complete root set.
- Prepare raw/inherited resource storage when a concrete consumer requires it.

Measurements: [compiler performance](../docs/compiler-performance.md).
Frontend work: [incremental frontend](frontend_review.md).
Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).
