# REPL stabilization — next release

Ship a non-experimental REPL for a documented execution subset. Keep the shared
semantics, Safety and VM; full LLVM parity and JIT are not release requirements.

## Acceptance work

- Define supported everyday programs through executable cases: text, collections,
  imports, generic functions/contracts, partial initialization, persistent owners
  and references, `#run` and `#if`. Inventory lowerer/verifier restrictions and
  distinguish unsupported features from semantic discrepancies.
- Extend existing native/VM comparisons for values, effects and cleanup:
  replacement, aliases, early exits, numeric boundaries and calls/virtual dispatch
  between old and new code units. Fix discrepancies within the supported scope.
- Complete allocation/resize failure sweeps for resource-bearing prelude semantic
  preparation: resolution, Safety, accepted-state rollback and retry. Source
  preparation, retained graph creation and publication checks already exist.
- Measure 10/100/1,000-command sessions and longer resource, definition and
  rejection workloads. Separate phase latency and retained memory; establish
  acceptance budgets and distinguish live results from reclaimable storage.
- Complete Unicode display-width handling. Verify cursor/rendering, multiline
  indentation, history, Ctrl-C/EOF and piped input using existing terminal and
  transport tests; record platform coverage.
- Publish the supported subset, resource policy and failure/reset guarantees in
  usage documentation, and run acceptance cases in CI before removing the label.

## Boundaries to preserve

- Unsupported operations can reject reachable bodies even in untaken branches.
  General FFI/native pointers, indirect calls, owning globals and some acquired
  layouts/indirect owning writes remain restricted; audit actual coverage.
- The prelude supplies output, allocation and tracing, not unrestricted System.
- Compilation rejection preserves accepted state. Traps/cancellation preserve
  completed effects, poison execution and require reset. Healthy reset/exit clean
  resources; execution is not transactional.
- Numbered results intentionally retain values. Measure other retained storage
  against live roots; coordinate reclamation with [compiler.md](compiler.md).

Known differential boundary: `text/26_string_view_trim` tests address identity
through unsupported `__reference_address`; ordinary trimming is covered by
`text/29_string_view_split` on both backends.

References: [usage](../docs/usage.md#experimental-persistent-repl),
[measurements](../docs/compiler-performance.md), `src/execution/interactive.zig`,
`src/5_codegen/bytecode/lower.zig`, `src/0_commands/repl{,_input}.zig` and
`src/execution_benchmark.zig`. External compile-time reads and cross-compilation
remain in [compiler.md](compiler.md); closures are unscheduled in [0.5.md](0.5.md).
