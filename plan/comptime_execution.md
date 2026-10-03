# Interactive execution and compile-time machinery

## Direction

Build on module reuse to shorten edit/evaluate cycles. Prototype with the
existing native execution path before choosing a VM, direct LLVM JIT, or a
combination. Interactive tooling is the goal; a tiered execution engine is one
possible implementation.

## Work to do

- [ ] Reuse modules and function specializations in a persistent compiler session,
  with dependency-aware invalidation and ordinary safety checks.
- [ ] Measure evaluation latency, separating compilation, emission, linking,
  and startup. Isolated submissions can precede persistent mutable values.
- [ ] Define which definitions/values survive inputs, cleanup on reset/exit,
  recovery after failed submissions, and redefinition with live values.
- [ ] Compare native execution, JIT, and a small typed interpreter/VM on actual
  interactive workloads. Reuse existing representations before adding an IR.
- [ ] If multiple executors are justified, share value/call/error/cleanup
  semantics and check parity with ahead-of-time execution.

Shared compile-time execution additionally needs effect restrictions,
deterministic build inputs, and execution limits. Transparent live-value migration,
arbitrary hot replacement, and tiered optimization are outside the initial scope.
