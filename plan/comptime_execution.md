# Bytecode execution

Release order: [0.4](0.4.md). Current commands and supported execution subset:
[usage](../docs/usage.md#experimental-bytecode-execution). Language semantics:
[compile-time execution](../description/50_comptime.md).

## Next

- Extend the ordinary REPL prelude with a persistent allocator through explicit
  checked host adapters.
- Improve unresolved-name diagnostics in retained sessions.
- Wire the source loader to retained selections and checked module-condition
  requests, then resume import/declaration discovery. The semantic session can
  evaluate closed Boolean recipes and retry after appending dependencies.
  ModuleSG retains directive source identities and recipes through cache
  serialization; the frontend retains source selection decisions independently
  of syntax trees.
  Do not analyze inactive branches or replace original source identities with
  rendered buffers.
  Append selected declarations through explicit module fragments, preserving
  physical graph ranges and the original module's lexical namespace.
- Complete staged request diagnostics without a source database. Support temporary
  type recipes without retaining identities from speculative graph tails.
- Define generic-function access to retained value bindings explicitly; do not
  introduce accidental captures or treat runtime session values as constants.

## Partial storage

- Extend partial layouts to choices and connect owning array elements to
  indexed cleanup identities.
- Extend acquired storage and release identities before enabling the allocator
  prelude; scalar host handles alone do not establish allocation receipts.

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
