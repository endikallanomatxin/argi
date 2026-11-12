# Body witnesses for reference-result summaries

## Missing obligation

A may-target list is not necessarily complete. Updating its known candidates
cannot justify leaving every other local reference unchanged. A reduced program
made this visible without concurrency inside the helper: it selected a local
alias from an array, retargeted that local, and returned the retargeted reference.
The temporal body visitor knew the replacement's input identity, while symbolic
summary inference still published only the original input. Starting a writer
after the helper returned bypassed the intended call-entry gate. The reduction
was compiled only, never executed.

This is a composition failure, not a missing array-specific concurrency rule.
The required relationship is:

    possible input origins witnessed at a return
        <= input origins represented by the published reference result

Validity roots alone cannot check this: independent symbolic inputs deliberately
share possible backing and lifetime roots. Their retained input identities can
distinguish origins without claiming physical disjointness.

## Reusing the temporal visitor

The implementation adds a bounded body-witness collection before final checks:

1. Keep evaluated entry argument facts for supported reference-result bodies.
2. Run the ordinary temporal body visitor against converged call summaries.
3. At normal returns with initialized output bindings, instantiate the current
   output summary in a cloned state.
   When it retains known input identities but omits a witnessed input origin,
   find that identity in the entry arguments' existing reference leaves.
4. Add the corresponding caller-relative InputPath as another ordinary input
   dependency of that output. This is a conservative alternative, not a new
   reference identity or authority. Must-relations weaken through the existing
   joinStorageAlternatives operation. Guarded output summaries are widened too.
5. Resume the ordinary summary fixed point and repeat until no new input-source
   alternatives appear. Callers therefore see the weaker summary before final
   validation, virtual conformance checking or cache publication.
6. Final body checking still rejects known input-origin omissions. Collection
   cannot publish body proofs or annotations, and its speculative diagnostics
   do not replace final diagnostics.

The source universe is finite: supported entry reference leaves and output
indices. Sources are deduplicated, never synthesized from arbitrary arithmetic
or paths that grow on recursive calls. Existing SCC propagation handles the
resulting summary changes. Persistent constraints contain caller-relative paths,
not proof-local graph addresses. Cache publications include the resulting normal
summary vocabulary, with no new serialized permission or runtime representation.

No recognition of array syntax was added to mutation-target inference. The same
body witness works when selection passes through functions or stored arguments.
The earlier may-target tracking still serves other effects and post-values; this
checkpoint does not claim it can all be removed.

## Scope and resource boundary

The bounded implementation covers direct reference outputs to plain execution
storage, reusing the existing predicate that excludes destruction, references,
virtual handles and raw native handles from the referent. It is not a method for
inventing ownership transfers, acquisition receipts or completion evidence from
possible reference aliases. Those need their own conservation requirements.

The check currently challenges summaries that retain known input identities.
It does not establish completeness for wholly unknown results, opaque captures,
structurally nested reference outputs, every caller-storage postcondition or
newly derived symbolic locations that are absent from entry argument leaves.
Fresh output dependencies and owners remain outside this bounded comparison.
Missing witness transport cannot be treated as an empty access footprint.
Recovering a result's origins also does not prove the helper's confinement.
If its may-access footprint stays unknown, calling it during an unrelated loan
can still be rejected. The tests extract first and then start the writer;
returned-value provenance and call-entry authority are separate obligations.

An explicit return expression that leaves its output binding uninitialized is
not refined by this increment. A compile-only contrast against the prior
compiler confirmed that the reduced expression-return case already has unknown
access and rejects the pending writer. Treat this as an existing precision
limit, not as evidence of another accepted race. In particular, do not remove
the known-summary guard and manufacture identity from an incomplete set of
body-witnessed origins. A complete output abstraction is needed to recover such
precision safely.

This is a checked refinement of one part of the abstraction, not a general proof
of summary soundness or race freedom. General physical extent publication,
owner transfer with cleanup and protected-access protocols remain open.

The next coverage requirement is separate from collecting more origins: a
known subset cannot certify that no other target is possible. Any stronger
refinement must track exhaustive coverage or forget unjustified target claims
while retaining validity obligations. In particular, a known/unknown join must
not become complete because one known input identity remains. Reuse this rule
for body facts and published summaries before adding further target recognizers.

## Regression contrasts

- 221X/222: selected local alias omitted by the old target recognizer, conflicting
  writer versus an independent replacement.
- 223X/224: the same contrast with a dynamic selection index.
- 225X/226: the replacement comes from a reference field in a by-value input;
  origin transport must select that field rather than the aggregate envelope.
- 227X: the returned replacement expires before use, without any pending task.
- Unit tests check weakening of exact reference relations, guarded-summary
  propagation, absence of fresh resources and idempotent source collection.

Acceptance of the independent variants is essential. Rejecting the helper
unconditionally would hide the inference defect and lose modular usability.

## Validation

The candidate passes 324 Debug safety unit tests and 321 concurrency/alias
program tests. Complete validation then passes 1,532 Debug internal tests
(one skipped) and 2,618 ReleaseSafe program tests (11 skipped), with no program
failures, leaks or error logs. All runs use one worker and a 6 GiB process limit.
Peak RSS is approximately 565 MiB for internal validation and 2.68 GiB for the
program build/run command. After removing unused fixture helpers, the seven new
cases are checked again with the same optimized compiler.

The next bounded implementation is [reference target coverage](reference_target_coverage.md).
It preserves an explicit incomplete-alternative fact through bodies and summaries.
It also documents a confirmed residual-write counterexample that this marker
alone does not close; collecting known origins cannot replace that obligation.
