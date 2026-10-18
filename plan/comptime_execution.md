# Bytecode execution

Release order: [0.4](0.4.md). Current commands and supported execution subset:
[usage](../docs/usage.md#experimental-bytecode-execution). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Next

- Execute and display an ordinary Argi REPL prelude establishing persistent
  assumed allocator, output and trace capabilities. Add checked host capability
  operations rather than injecting unchecked bindings or bypassing safety.
- Improve unresolved-name diagnostics in retained sessions.
- Resolve computed module-level `#if` before discovering selected imports and
  declarations. Preserve source identities and do not analyze inactive branches.
- Complete staged request diagnostics without a source database. Support temporary
  type recipes without retaining identities from speculative graph tails.
- Define generic-function access to retained value bindings explicitly; do not
  introduce accidental captures or treat runtime session values as constants.

## Execution coverage

- Extend partial initialization and trace reporting.
- Complete evaluated cleanup identities for owning replacement through indexed
  storage and unresolved/retargetable references, shared with native lowering.
- Extend scalar representations and explicit host-call capabilities only through
  checked signatures and evidence.
- Add configurable quotas and cancellation at safe points. Measure repeated
  execution and retained memory before considering JIT.

## Invariants

- VM execution and compile-time execution consume checked language semantics;
  neither reimplements dispatch, borrowing or ownership inference.
- Source/semantic publication is transactional. Executed effects cannot be rolled
  back; traps poison execution until reset.
- Session values, including numbered expression results, retain ordinary loans
  and cleanup. Healthy reset/exit executes checked cleanup before releasing them.
- Evaluator storage, references and native handles cannot escape as constants.
  Target widths/layouts must match supported execution semantics.
- Keep graph identities stable across submissions. Retained metadata must outlive
  bytecode and values that reference it; rejected candidates publish nothing.

## Validation

Compare bytecode and AOT for each added capability. Exercise cross-command loans,
partial moves, reinitialization without alias revival, owning expression results,
cleanup, rejected submissions, traps and reset. Test `#run` and computed `#if`
through retained sessions as well as native compilation, including inactive
branches, cycles, allocation failures and rejected evaluator-resource escapes.
