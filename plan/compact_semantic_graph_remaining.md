# Compact semantic graph: parity checkpoint

The compact semantic graph branch now passes all registered program tests:

- 661 / 661 program tests pass (`zig build test-programs`).
- Internal tests pass (`zig build test-internal`).
- The combined `zig build test` target passes.

No known red parity tests remain. Abstract contracts are specialized from
concrete static implementers, including typed local `#reach` bindings and
reached inputs to binary operators. `Virtual` remains the explicit dynamic
dispatch mechanism. An explicit `~System` transfer is valid; implicit copying
of `System` remains invalid.

Before integration, review the branch-wide diff and validate in the intended
release environment. New failures should be investigated against this
checkpoint rather than the historical inventory in
`plan/refactor_regressions.md`.
