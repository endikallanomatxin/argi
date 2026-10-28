# REPL stabilization

Remove the experimental label only after establishing a supported scope and
repeatable acceptance checks. Keep ordinary semantics, Safety and the shared VM;
JIT and complete native-backend parity are not prerequisites.

## Current boundaries

- Bytecode lowering rejects unsupported operations in reachable bodies, including
  untaken branches. General native pointers/FFI, indirect calls, owning globals,
  some acquired layouts and owning writes through runtime references remain
  restricted. Inventory actual lowerer/verifier rejections before expanding scope.
- The prelude provides output, allocation and tracing, not unrestricted `System`.
  Compile-time external reads additionally require dependency/cache tracking.
- Compilation rejection preserves accepted state. Traps and cancellation preserve
  completed effects, poison execution and require reset; user cleanup cannot
  safely unwind a poisoned context. Healthy reset and exit use checked cleanup.
- The semantic graph is shared, not copied per command. Frame identities,
  acquisition tombstones, executable metadata and some immutable value storage
  remain retained until reset. Numbered results intentionally retain their values.
- Value display is bounded but basic: references are opaque and choices display
  ordinals. Terminal editing lacks Delete and full Unicode display-width handling.

## Work and exit criteria

1. Define the everyday supported scope using executable examples: text and
   collections, imports, generic functions/contracts, partial initialization,
   persistent owners/references and `#run`/`#if`. Classify each gap as unsupported
   language functionality, a VM limitation or a semantic discrepancy. Prioritize
   demonstrated consumers; do not add REPL-specific semantic fallbacks.
2. Audit and extend existing native/VM comparisons, rather than building another
   test runner. Compare values, observable effects and cleanup counts. Cover
   replacement, aliases, early exits, numeric boundaries and dispatch between old
   and new code units; retain internal tests for exhaustive local rules.
3. Close the failure-lifecycle matrix: rejected commands and allocation failures
   publish nothing; traps, budget exhaustion, cancellation and host callback
   failures prevent further execution until reset. Check host-owned resources,
   stale references and reset/exit failures explicitly. Document which effects
   cannot be undone and how context-owned resources are released without user
   cleanup. Never promise transactional rollback of execution.
4. Measure 10/100/1,000-command sessions, then longer resource/definition/rejection
   workloads using the existing execution benchmark. Separate setup, frontend,
   lowering, verification and execution; report per-command latency and retained
   memory, distinguishing live results from reclaimable storage. Establish
   reproducible budgets from these measurements, including repeated reset cycles.
   Coordinate reclamation with [compiler follow-ups](compiler.md).
5. Improve named variant/record presentation and ordinary terminal editing without
   dereferencing or copying owners for display. Verify Unicode cursor/rendering,
   Delete, multiline input, history, Ctrl-C/EOF and piped input. Keep real-terminal
   tests alongside transport tests and document platform coverage.

Before removing the label, publish the supported subset, failure/reset contract
and measured resource policy in usage documentation, and make their acceptance
cases part of existing CI. Fix semantic divergences within that scope; explicitly
document exclusions. Existing differential tests and CI are a starting point,
not evidence that this acceptance review has already passed.

References: [usage](../docs/usage.md#experimental-persistent-repl),
[measurements](../docs/compiler-performance.md), `src/execution/interactive.zig`,
`src/5_codegen/bytecode/lower.zig`, `src/0_commands/repl{,_input}.zig` and
`src/execution_benchmark.zig`. General cross-compilation and external compile-time
dependencies remain in `compiler.md`; closures remain unscheduled in `0.5.md`.
