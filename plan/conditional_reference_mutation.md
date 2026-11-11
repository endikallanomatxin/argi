# Reference mutation across alternatives

## Problem and scope

The uniform unknown-call gate in cfbcf400d checks may-access effects before
completion postconditions. It does not make an inaccurate returned value safe.
A helper could retarget a reference conditionally, or through a selected alias,
while the caller retained the old local value. The stale reference could escape
before a loan began or survive the new target's scope. The unsafe reductions
were compiled only, never executed.

This checkpoint retains possible mutation destinations and weakly updates their
stored values. It changes neither sequential reference exclusivity nor execution
receipt authentication. It is a bounded composition correction, not a proof of
the complete concurrency model.

## Rules

1. A reference copy does not duplicate authority. A possible destination is not
   an exact referent, a disjointness proof, initialization or ownership evidence.
2. A definite write to one established destination can replace its value.
   Conditional writes and writes to multiple possible locals must join each
   incoming value with the replacement. Preserved cleanup facts are not writes.
3. Forgetting singleton identity must not forget the possibility of mutation.
   Concrete candidates retained beside symbolic identities receive weak updates;
   even a singleton candidate is not a complete target set.
4. Structural projection preserves alternatives rather than choosing a sibling
   or discarding the symbolic side of a mixed reference. A symbolic destination
   is not exclusive when a concrete alternative is also possible.
5. Mutating a reference-bearing local field updates its current value facts.
   Its initializer cannot permanently describe the value returned after mutation.
   Projected mutation candidates are retained separately from exact local addresses.
6. A callee's possible initialized common post-value contributes a replacement
   alternative. May-effects still authorize access before completion, and unstable
   reference sources cannot regain old observation relations through capability
   overlays. Lifetime dependencies alone never establish physical independence.

## Representation and composition

ValueFacts retains mutation_places as conservative concrete mutation candidates.
Reference copies retain them; derived views drop slot identities. Merging facts
unions candidates without manufacturing referenced_place. The checker weakly
stores into known candidates and retains symbolic alternatives as well. Equality
includes these facts so cached/path state comparisons cannot silently ignore them.

Summary inference keeps local candidate nodes separate from exact address nodes.
They remain proof-local and never become graph IDs inside published summaries.
Whole local aliases retain alternatives through reassignment. Explicit aggregate
member selection and projected reference writes retain the selected candidates;
current local ValueEffects use the existing selected-value store operation.
Candidate queries can weaken values but cannot prove a complete target set.

### Projected helper results

A helper returning a reference stored in an input record publishes a dependency
on that field, not on the whole input. Mutation-target substitution must follow
the published projection into the evaluated argument. Dropping nonempty paths
lost the destination of `select_target(handle)` even when `handle.target` was
already represented. Both forms now use the same existing projection operation;
validity-only dependencies and erased storage domains still grant no candidate.
This supplies may-targets only, never a strong-update or independence proof.

The 215X regression compiled before the correction: a helper returned a stored
alias, another helper retargeted its referent, and the old returned facts allowed
a read during a writer loan. It was not executed. The 216 counterpart selects
an independent replacement and must still build and run successfully.

The finite Zig oracle in reference_observation_model.zig checks strong/weak
updates against all stores in a two-location, two-reference model. It includes
conditional and incomplete-singleton contrasts. It is a design oracle; the
checker regressions exercise the real implementation independently.

## Regression contrasts

- 205X/206: conditional helper replacement versus an independent replacement.
- 207X: returned alias is used after lending its real target, so an unknown-call
  rejection during the earlier extraction cannot substitute for correct facts.
- 208X/212X: replacement target expires, both through a returned reference and
  through caller-local storage. These exercise sequential temporal safety.
- 209X/210X: alias reassignment and a result-returning conditional helper.
- 211X/213X/214: stored alias, later replacement of its field, and the safe
  independent counterpart. 121/177/201/204 remain positive acceptance cases.
- Production unit tests check weak concrete updates and mixed symbolic/concrete
  alternatives, including projection and preservation of both old/new lifetimes.

## Validation

The broad candidate passes 1,528 Debug internal tests (one skipped) and 2,605
ReleaseSafe program tests (11 skipped), with no program failures, leaks or error
logs. A subsequent mixed-alternative audit added two failing-then-passing tests
and corrected symbolic exclusivity/projection. The resulting 322-test Debug
safety run passes, as does the final 308-program concurrency/alias selection
(zero failures, skips, leaks or error logs). All runs are serial under a 6 GiB
process limit. The full suite predates the final mixed-alternative increment;
the affected program selection revalidates that increment.

## Remaining limits

Known mutation candidates do not describe all possible unknown aliases. This
checkpoint does not establish a general complete finite-target abstraction,
general pointer arithmetic aliasing, or every guard/outcome-specific value
transformer. Those need explicit completeness or conservative unknown-state
handling, never authority inferred from a partial candidate list. Broad native
construction assumptions, erased physical extent publication, owning task
transfer and protected-access protocols remain separate work. Passing these
regressions does not establish general language soundness.

The projected-helper correction passes 322 Debug safety unit tests and 310
concurrency/alias program tests, with no failures, skips, leaks or error logs.
The new failing/passing contrast also passes in isolation. Validation uses one
worker under a 6 GiB process limit; measured peak RSS is below 450 MiB.
