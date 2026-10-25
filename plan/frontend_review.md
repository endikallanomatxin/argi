# Incremental frontend

Measurements and commands: [compiler performance](../docs/compiler-performance.md#incremental-resolution-profile).

- Profile remaining resolution, completion and verifier work in growing sessions
  before replacing global scans with pending work. Preserve validation of old
  entities completed by a new transaction. Compare `binding_initializers` with
  `expression_types` before making binding propagation incremental.
- Audit persistent resolver state: keep scratch work local and reduce what needs
  rollback. Pending-queue copying is not a demonstrated bottleneck in measured
  sessions; avoid replacing it with a more complex transaction mechanism.
- Clarify pass prerequisites and produced facts. Review ownership operand staging
  against shared lowering without duplicating evaluation or cleanup.
- Measure invariant work in generic specialization before sharing representation.
- Reproduce and improve diagnostics for inferred nested module-level aggregate
  constants that fail graph verification; submodule fixtures use explicit types.

Compare 10, 100 and 1,000 commands, including rejections and core/prelude workloads.
Keep existing differential and allocation-failure coverage. New IRs, general
invalidation and semantic parallelism need evidence of a concrete benefit.
