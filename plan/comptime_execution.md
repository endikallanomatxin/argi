# Execution follow-ups

- Record external compile-time reads as build dependencies before exposing those
  host capabilities. Define their reproducibility and cache identity.
- Separate host execution from target semantics for cross-compilation.
- Investigate reclaiming transient aggregate backing and metadata in the execution
  arena without invalidating published values or references. Call-slot buffers
  already reuse backing independently of dead frame identities.
- Prepare raw/inherited resource storage when a concrete consumer requires it.

Measurements: [compiler performance](../docs/compiler-performance.md).
Frontend work: [incremental frontend](frontend_review.md).
Current behavior: [usage](../docs/usage.md#experimental-bytecode-execution).
