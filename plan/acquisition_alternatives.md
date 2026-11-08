# Acquisition guarantees across alternatives

Checkpoint following 5f0b98bbf. Ownership, lifetime and storage-acquisition
permission remain distinct. This correction reuses ValueEffect, InputPath and
existing caller-side acquisition authorization; it introduces no permission kind,
runtime receipt or source syntax.

## Invariant

A possible acquisition identity is useful for duplicate-consumption checks, but
it cannot prove that every returning alternative carries an available permission.
A contract publishing ownership alone does not publish acquisition authority.
Joining values must preserve that distinction recursively through aggregates.

A missing choice payload is excluded only when a known discriminant establishes
that the branch returns another case. Otherwise the payload joins with the
unknown alternative. A symbolic input is not empty: its payload-relative
precondition must be retained and checked against the evaluated caller value.
Known different error outcomes do not weaken the guarantees of a success payload.

Typed joins distinguish record fields, static array indices and choice variants.
These path categories must not be interchanged, including inside nested owners.
Sparse array summaries overlay only represented elements; the array length does
not cause expansion into all physical slots. Capability reads of array elements
use the same projections as their output summaries.

## Evidence

The unit reduction for unknown choice alternatives failed before the correction.
The array-path unit also fails when the element projection is replaced by a
record-field projection. The positive symbolic-input cases require projected
caller authorization rather than automatic rejection.

| Fixture | Required result |
| --- | --- |
| types/420_choice_acquisition_input | Forward an authenticated choice input and establish its selected acquisition |
| types/421X_choice_acquisition_without_published_permission | Reject a choice input whose erased factory publishes ownership only |
| types/422_array_acquisition_input | Forward an authenticated array element and establish it |
| types/423X_array_acquisition_without_published_permission | Reject an array element whose erased factory publishes ownership only |

Both negative programs compiled on published 5f0b98bbf. They were compiled only,
never executed. The candidate accepts the positive builds and rejects both
negatives for missing authenticated acquisition permission.

Full isolated Debug validation passes: 1,504 tests, one skipped, 579,748 KiB peak
RSS and no swaps. ReleaseSafe compilation succeeds. Full ReleaseSafe program-suite validation
passes: 2,546 passed, 11 skipped, zero failures, leaks or error logs. Builds and tests run serially under a 6 GiB process limit.

## Limits

This does not complete physical provenance, checked backing derivation, owner
transfer between executions, or protected-access protocols. In particular, the
positive ArrayView reduction and heterogeneous collection authorization remain
open. The broader acceptance gates remain in [resource_authority.md](resource_authority.md).
