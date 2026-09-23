# Compact semantic graph: remaining parity work

This is the active inventory for the final semantic-parity work on
`compact-semantic-graph-chatgpt`. It records current causes and recommended
work order, not a history of every regression fixed during the refactor.

Keep this document small and current. When a cause is fixed and its focal and
related tests pass, remove that cause and its test names instead of marking a
permanent completed checklist. Update the measured checkpoint after each
global run. Design questions that cannot be settled as implementation details
belong in `plan/refactor_regressions.md` and should only be linked from here.

## Measured checkpoint

Current checkpoint after resolving typed local `#reach` and allowing explicit
`System` moves:

- 655 / 661 program tests pass.
- 6 / 661 program tests fail.
- All six failures share an incomplete static-implementer propagation path.

## Resolution and generic materialization

### Static implementers through propagated `#reach`

Affected tests:

- `feature_tests/text/12_string_concat`
- `feature_tests/text/13_string_concat_string`
- `feature_tests/text/14_string_concat_string_view`
- `feature_tests/text/15_string_view_concat_c_string`
- `feature_tests/text/16_string_view_concat_string_view`
- `feature_tests/text/17_string_view_concat_string`
Operator resolution preserves the eventual `Errable` output type. All six
tests reach `string_with_capacity` from `concat_views`, whose `allocator`
binding is reached through a function boundary. Local typed `#reach` now
selects and records a concrete static implementer without widening the
visible `$&Allocator` interface; this closes `system/25`. The same identity
must be carried when a reached parameter is propagated into and specialized
through another function. Abstract inputs monomorphize; `Virtual` alone opts
into runtime dispatch. Do not bind the abstract declaration as its own
implementer or relax generic inference to force these tests through.

## Recommended work order

1. Carry concrete static-implementer evidence through propagated reached
   parameters and function specialization.
2. Verify the six String concatenation paths and global suite without
   changing their visible abstract interfaces.
