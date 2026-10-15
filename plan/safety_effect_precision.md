# Safety effect precision

## Boundary

Extend effects under conjunctions of structural choice selectors from entry
inputs and returned outputs, including fields and nested payloads. Ordinary
numeric predicates and dynamic index relations remain outside scope.
Evaluate Boolean selectors separately if a consumer needs them.

## Remaining design work

- Apply each joint guard consistently to generation, hidden storage, initialization,
  ownership, consumption, and cleanup; payload dependencies alone are insufficient.
- Preserve relations across matches, early returns, propagation, and branch-assigned
  forwarding when every selected exit proves them.
- Keep permissions (possible effects) separate from guarantees (definite facts).
  Union possible effects and intersect guarantees at joins.
- Refine actual caller identities under the original call and current generations.
  Never restore snapshots or revive resources after later writes/invalidation.
- Share guards/templates rather than multiplying independent tag combinations.
  Bound recursive paths and loop histories; measure worklist convergence separately.
- Diagnose unrepresentable proofs rather than silently weakening explicit contracts.

## Acceptance cases

- Retain a preexisting reference after failed reserve/insertion when preserved.
- Forward fallible owners and borrowed outputs through ordinary wrappers.
- Extract hidden contents, then empty storage without losing output dependencies.
- Retry failed close without permitting double cleanup.
- Reject stale generations, mixed evidence from independent calls, overlapping
  transfers, and resource manufacture after conservative joins.
- Measure representation size and reevaluations on core-sized examples.
