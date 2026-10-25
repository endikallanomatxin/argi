# Incremental frontend review
These are risks to measure, not demonstrated regressions or release commitments.

- **Global verification:** `verifyUnit` rechecks accumulated pools on each command.
  Measure its components, including symbol owner lookups through the linear
  `moduleForDeclaration`, before designing incremental verification. Preserve
  validation of completed old entities and reject malformed transactions.
- **Global scans:** dereference/address/binding/assignment materialization, generic
  types and error-reason inference revisit pools during fixed-point resolution.
  Existing behavior can become costly over an accumulating REPL graph. Measure
  visits and rounds before replacing scans with pending work.
- **Transactions:** pending-worklist checkpoints copy entries for rollback.
  Measure their cost and retained memory as sessions grow; preserve speculative
  rollback and stable published identities.
- **Ownership transformations:** staging fallible operands adds lexical owners and
  rewrites semantic expressions. Assess the boundary between semantic finalization
  and shared lowering; preserve the existing differential cleanup/evaluation-order
  coverage. Semantic rewriting alone does not justify another IR.
- **Pass dependencies:** type materialization, sugar and error propagation have
  ordering requirements. Audit which prerequisites are explicit and which rely on
  knowledge of the resolution driver before restructuring it.
- **Generic instances:** specialization rebuilds concrete semantic bodies from
  parameterized IR. Measure invariant work and memory before sharing subtrees;
  sharing also has bookkeeping and lifetime costs.
- **Conditional source scanning:** share lexical rules with the tokenizer rather
  than maintaining independent recognition of strings, comments and delimiters.
- **Parallelism:** global semantics, Safety and codegen remain sequential. Keep the
  single main transaction; profile sequential work before considering concurrency.

Most of these structures predate the branch. Distinguish existing costs from work
introduced or amplified by incremental sessions. Compare 10, 100 and 1,000 commands,
including time per interval, phase costs and retained memory. Current baseline
measurements and reproduction commands: [compiler performance](../docs/compiler-performance.md#incremental-resolution-profile).
Use the existing execution benchmark. No new IR, scheduler or general invalidation
system without a demonstrated need.
