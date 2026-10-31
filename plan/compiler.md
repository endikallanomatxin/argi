# Compiler follow-ups

REPL guarantees and acceptance evidence are recorded in
[the acceptance notes](../docs/repl-acceptance.md). Prioritize demonstrated
correctness or cost issues in the follow-ups below.

## Resolution

- Replace temporary resolver communication state with explicit results. Preserve
  useful diagnostics across speculative rollback, including readonly generic
  virtual conversions.
- Reduce measured redundant binding/type sweeps, propagation and Safety work in
  specialization workloads. Revisit older entities completed by new facts;
  ownership also needs operands outside execution reachability.

## Safety

- Extend conditional storage effects through stored results, indirect outputs
  and loops, preserving intervening writes and caller identities.
- Extend hidden retention/replacement and grouped opaque mappings through output
  fields when a consumer needs them.
- Represent hidden storage and cleanup identities before virtualizing Resizable.

## Execution

- Track external compile-time reads in build dependencies/cache identity.
- Separate host execution from target semantics for cross-compilation.
- Reclaim immutable aggregate payloads using every live root: results, cross-frame
  writes, session/acquired storage, virtual descriptors and public `Vm.invoke`
  results. Preserve their current validity until reset/destruction or a fresh run.
  Use `aggregates` and `float_parsing` as controls; local aggregate writes already
  reuse mutable cells. Baselines and reproduction commands belong in the
  [performance notes](../docs/compiler-performance.md).

Validate with growing sessions, allocation failures, rollback and native/VM
comparisons. Safety extensions need aliasing and duplicate-cleanup rejections.

References: [resolution boundaries](../docs/semantic-resolution.md),
[Safety](../description/34_safety_model.md#precision-of-safety-effects),
[virtual contracts](../description/134_virtual_types.md).
