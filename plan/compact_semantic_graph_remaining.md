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

Current checkpoint after restricted-lifetime propagation and owned-root cycle
validation:

- 623 / 659 program tests pass.
- 36 / 659 program tests fail.
- 22 failures already reject invalid source and differ only in diagnostic
  wording or source location.
- 14 failures expose semantic or resolution work, including two aggregate
  regression slices that remained red after repairing nested cleanup layout.

## Resolution, generic materialization, and contextual typing

### Associated generic discovery

Affected tests:

- `feature_tests/collections/17_string_hash_map_baseline`
- `feature_tests/collections/37_dynamic_array_associated_copy_reasons`

The declarations exist, but candidate discovery or substitution does not
produce a callable concrete instance. The first test reports no `put`; the
second reports no `require_array_reasons`. Instrument candidate rejection
before changing inference rules, and distinguish declaration discovery from
associated-type substitution.

### Contextual integer typing through `#reach`

Affected test:

- `feature_tests/system/25_local_typed_reach_binding`

The `.capacity` literal becomes `Int32` before the selected call supplies the
expected `UIntNative` context. Preserve an unresolved literal until call
materialization or reapply the selected input context. Do not make every
`inferInputType` failure discard a candidate; that previously caused broad
regressions.

### Binary operator materialization and output propagation

Affected tests:

- `feature_tests/text/12_string_concat`
- `feature_tests/text/13_string_concat_string`
- `feature_tests/text/14_string_concat_string_view`
- `feature_tests/text/15_string_view_concat_c_string`

The intended `+` overload is either not selected or loses its `Errable`
output during materialization. The fallback then diagnoses pointer arithmetic,
or a following match sees `&String` instead of the choice result. Treat this as
an operator-call pipeline issue rather than special-casing String.

### Erased abstract free-function calls

Affected tests:

- `feature_tests/text/16_string_view_concat_string_view`
- `feature_tests/text/17_string_view_concat_string`

These reach `string_with_capacity` with an erased `$&Allocator` but no concrete
implementer from which to specialize its abstract-contract function. This is
an open language-design question documented in
`plan/refactor_regressions.md`. Do not bind the abstract declaration as its own
implementer or otherwise relax generic inference to force these tests through.

## Safety and ownership semantics

### Fresh opaque extraction uses a stale generation

Affected tests:

- `feature_tests/ownership/156_fresh_opaque_extraction_after_refresh`
- `feature_tests/ownership/161_fresh_opaque_wrapper_extraction_after_refresh`

After a storage binding is reinitialized with a new allocation, a reference
extracted from its new opaque slot still depends on the old ended generation.
The wrapper case shows that the same invariant must survive function summaries.
The fix must refresh only the alias used to reinitialize storage, not sibling
aliases. Verify the ownership 148--162 neighborhood.

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
- `feature_tests/ownership/49X_structural_field_use_after_move`
- `feature_tests/ownership/50X_branch_may_move_value`
- `feature_tests/ownership/51X_loop_may_move_value`
- `feature_tests/ownership/85X_semantic_relocation_double`
- `feature_tests/ownership/202X_conditional_expression_joins_input_post_state`
- `feature_tests/ownership/214X_conditional_opaque_consumption_invalidates_source`

The remaining differences are generic `value was moved` or
`value may be uninitialized` messages, lost root/place names, reporting order,
or source locations. Preserve the existing temporal joins and move origins.

Lifetime, provenance, and raw-pointer reporting:

- `feature_tests/ownership/40_raw_pointer_establish_fresh`
- `feature_tests/ownership/42X_reference_use_after_root_end`
- `feature_tests/ownership/43X_inferred_cleanup_ends_internal_root`
- `feature_tests/ownership/45X_cross_root_cycle_stale_edge`
- `feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance`
- `feature_tests/ownership/53X_pointer_inputs_may_alias`
- `feature_tests/ownership/55X_deinit_through_alias_read`
- `feature_tests/ownership/57X_return_reference_to_local`
- `feature_tests/ownership/58X_null_safe_reference`
- `feature_tests/ownership/59X_branch_deinit_then_use`
- `feature_tests/ownership/61X_borrowed_foreign_pointer_fresh_root`
- `feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip`
- `feature_tests/ownership/63X_malloc_direct_safe_cast`
- `feature_tests/ownership/284X_integer_cannot_establish_any_reference`

These report the intended safety rule but differ in wording or location from
the expectations.

Reached-default reporting:

- `feature_tests/io/26X_print_without_system`

Resolution knows that `print` cannot obtain its required reached value, but
emits a generic no-overload diagnostic instead of explaining the unavailable
`#reach` input.

## Regression slices requiring separate diagnosis

- `feature_tests/testing/13_collections_text_regression_slice`
- `feature_tests/testing/14_core_path_regression_slice`

The first ends a root during deferred String cleanup after formatting and
payload moves. The second loses a live dependency through Path construction or
its function summary. Both remained red after correcting the nested
auto-deinit descriptor layout, so they are no longer assumed to be consequences
of `ownership/60`. Re-run the first after opaque-generation work, then diagnose
each remaining slice independently.

## Recommended work order

1. Repair opaque-domain generation refresh in direct and summarized paths, then
   re-run the collections/text regression slice.
2. Diagnose the core Path regression slice if it remains independent.
3. Restore binary operator materialization and `Errable` output propagation.
4. Diagnose generic candidate discovery and contextual literal typing without
   globally tightening inference.
5. Consolidate move/place/provenance diagnostics.
6. Leave erased abstract calls and canonical `System` identity pending their
   documented language-design decisions.
