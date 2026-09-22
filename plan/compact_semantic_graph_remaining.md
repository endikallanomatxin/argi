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

Current checkpoint after diagnosing unavailable reached defaults:

- 650 / 661 program tests pass.
- 11 / 661 program tests fail.
- 1 failure already rejects invalid source and differs only in diagnostic
  wording or source location.
- 10 failures expose semantic or resolution work.

## Resolution, generic materialization, and contextual typing

### Associated generic discovery

Affected tests:

- `feature_tests/collections/37_dynamic_array_associated_copy_reasons`

The declaration exists and input inference reaches constraint validation. The
parameterized implementation
`DynamicArray#(.t: Type: FalliblyCopyable#(.reasons: element_reasons))`
uses `element_reasons` as an implicitly inferred associated parameter. The
compact abstract-relation lowerer currently records that name as an external
type rather than a parameter, so matching the concrete `FallibleValue`
implementation cannot bind its `(..copy_failed)` reasons. Restore inferred
associated parameters in relation lowering; do not weaken choice equality or
constraint validation.

### Erased abstract free-function calls

Affected tests:

- `feature_tests/text/12_string_concat`
- `feature_tests/text/13_string_concat_string`
- `feature_tests/text/14_string_concat_string_view`
- `feature_tests/text/15_string_view_concat_c_string`
- `feature_tests/text/16_string_view_concat_string_view`
- `feature_tests/text/17_string_view_concat_string`
- `feature_tests/system/25_local_typed_reach_binding`

Operator resolution now preserves the eventual overload output type and scores
contextual literals consistently with ordinary calls. All six tests therefore
reach `string_with_capacity` with an erased `$&Allocator` but no concrete
implementer from which to specialize its abstract-contract function. This is
an open language-design question documented in
`plan/refactor_regressions.md`. Do not bind the abstract declaration as its own
implementer or otherwise relax generic inference to force these tests through.

`system/25` reaches the same boundary through an explicitly typed local
`$&Allocator` binding and the abstract `String.init` initializer. Its integer
literal passes contextual `UIntNative` scoring; the final diagnostic displays
the earlier `Int32` type only after specialization fails. Do not treat that
display as a literal-inference failure.

## Safety and ownership semantics

### Escaping provenance after partial aggregate moves

Affected test:

- `feature_tests/ownership/60_partial_field_move_cleanup`

Nested auto-deinit descriptors now retain contiguous field ranges, but the
valid `Pair` returned by `make_pair` still appears to depend on a local storage
generation. Trace which generation survives the move into the `Errable`
payload before changing cleanup or escape rules; this is a provenance-transfer
bug, not a reason to permit local references to escape.

### Canonical non-movable `System`

Affected test:

- `feature_tests/ownership/35X_system_move_by_value`

This remains an open language-design question in
`plan/refactor_regressions.md`: the compact graph has no canonical capability
identity or non-movable property for core `System`. Do not implement the rule
by comparing a displayed type name.

## Correct rejection with stale diagnostics

These tests already reject invalid source. They should be addressed after the
remaining semantic acceptance/rejection bugs unless a semantic change touches
the same reporting path.

Move-state reporting:

- `feature_tests/ownership/14X_use_after_move`

The remaining difference is reporting order: copy insertion rejects the
second use before Safety can use the stored move origin. Projected field and
array reads already preserve root/place names, initializedness, and move
locations. Preserve the existing temporal joins and move origins.

## Recommended work order

1. Diagnose generic candidate discovery and contextual literal typing without
   globally tightening inference.
2. Correct move/copy diagnostic precedence and escaping aggregate provenance.
3. Leave erased abstract calls and canonical `System` identity pending their
   documented language-design decisions.
