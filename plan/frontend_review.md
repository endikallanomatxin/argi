# Frontend review after the merge

Investigate after merging `feature/bytecode-execution` into `develop`.
These are risks to measure, not demonstrated regressions or release commitments.

- **Global scans:** dereference/address/binding/assignment materialization, generic
  types and error-reason inference revisit pools during fixed-point resolution.
  Existing behavior can become costly over an accumulating REPL graph. Measure
  visits and rounds before replacing scans with pending work.
- **Transactions:** pending-worklist checkpoints copy entries for rollback.
  Measure their cost and retained memory as sessions grow; preserve speculative
  rollback and stable published identities.
- **Ownership transformations:** staging fallible operands adds lexical owners and
  rewrites semantic expressions. Validate evaluation order, exactly-once execution
  and cleanup in LLVM, VM and `#run` before the merge. Later, assess responsibility
  boundaries with evidence; semantic rewriting alone does not justify another IR.
- **Pass dependencies:** type materialization, sugar and error propagation have
  ordering requirements. Audit which prerequisites are explicit and which rely on
  knowledge of the resolution driver before restructuring it.
- **Generic instances:** specialization rebuilds concrete semantic bodies from
  parameterized IR. Measure invariant work and memory before sharing subtrees;
  sharing also has bookkeeping and lifetime costs.
- **Parallelism:** global semantics, Safety and codegen remain sequential. Keep the
  single main transaction; profile sequential work before considering concurrency.

Most of these structures predate the branch. Distinguish existing costs from work
introduced or amplified by incremental sessions. Compare 10, 100 and 1,000 commands,
including time per interval, phase costs and retained memory; the reported
20.8/22.1 seconds in frontend/publication is a lead, not attribution to these scans.
Use the existing execution benchmark. No new IR, scheduler or general invalidation
system without a demonstrated need.
