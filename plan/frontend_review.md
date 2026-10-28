# Incremental frontend

Measurements and commands: [compiler performance](../docs/compiler-performance.md#incremental-resolution-profile).

- Profile remaining resolution, completion and verifier work in growing sessions
  before replacing global scans with pending work. Preserve validation of old
  entities completed by a new transaction. Current measurements favor expression
  propagation and assignment contextualization over a binding-inference worklist.
  Growing live bindings also spend significant time copying continuation facts.
- Audit remaining persistent lookup and diagnostic state: keep scratch work local
  and reduce what needs rollback. Pending-queue copying is not a demonstrated
  bottleneck in measured sessions; avoid a more complex transaction mechanism.
- Clarify pass prerequisites and produced facts. Review ownership operand staging
  against shared lowering without duplicating evaluation or cleanup.
- Measure invariant work in generic specialization before sharing representation.

Compare 10, 100 and 1,000 commands, including rejections and core/prelude workloads.
Keep existing differential and allocation-failure coverage. New IRs, general
invalidation and semantic parallelism need evidence of a concrete benefit.
