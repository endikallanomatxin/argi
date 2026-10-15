# Contract follow-ups

- Deferred: joint virtualization of hidden participants. Needs a concrete consumer,
  joint ownership/lifetimes, and representable results.
- Deferred: broader symbolic compile-time relations. Preserve input-first selection;
  no inverse inference from associated results or general constraint solver.
- Distinguish definite signature-instantiation failures from missing bindings,
  without reporting errors from losing candidates.
- Profile substitution maps and materialization sweeps before changing storage.
  Preserve default/signature identities and speculative rollback.
- Define invalidation before caching validated global graphs or safety summaries.

The deferred features do not block VM/JIT. Measurement commands:
[compiler performance](../docs/compiler-performance.md).
