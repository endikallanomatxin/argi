# Precision of abstract safety effects

## Structural boundary

Use structural value facts and effects guarded by one discriminant, including
its nested payload discriminants. Do not retain conjunctions between independent
discriminants, predicates over ordinary values, or element-by-element dynamic
index relations. This boundary guides further effect dimensions; generation
effects already use individual choice selectors and conservative fallback
summaries.

Boolean status outputs are also finite discriminants in principle. Supporting
them would not inherently require arithmetic predicates, but syntax and demand
should be evaluated separately. Existing choice outputs are the initial target;
do not equate a future boolean selector with reasoning about arbitrary counts.

The boundary concerns independence of discriminants, not the number of outputs.
One output's variant may control facts about every output and input. Conversely,
two choice fields inside one record can be independent discriminants. Nested
choices along a payload path are structural alternatives of one returned value
and should not be excluded merely because the syntax is nested.

A body can contain arbitrary branches. Its inferred summary conservatively
forgets conditions outside the boundary. An explicit contract asking for an
unsupported relation must receive a diagnostic rather than silent weakening.
Do not change language behavior at an arbitrary count of branches or facts.

Callers can test several independent results, including in nested source blocks.
Each test refines the independently established facts for that call. The excluded
relation is an additional guarantee that requires their conjunction, not the
ability to write nested control flow or use independent contracts together.

## Evidence from existing code

| Existing operation | Precision needed | Consequence of omitting it |
| --- | --- | --- |
| Reader, Writer, BlockReader, BlockWriter | Separate success payload facts from error-tracer dependencies | Scalar successful results inherit unnecessary error dependencies |
| Allocator.allocate | Conditional fresh ownership and dependencies on the allocator; preserve concrete resource roles | Erased calls lose owning results or invent acquisition guarantees |
| DynamicArray.ensure_capacity and dynamic_array_grow_growing | Error preserves old backing generations; success may replace them | References expire conservatively even after allocation failure |
| OwnedHashMap.reserve | The same outcome distinction for table roots and shape; sibling roots change together | Callers must reacquire loans even on failure; the implementation documents this workaround |
| OwnedHashMap.put | Transfer entries into hidden storage on success, destroy passed owners on failure, invalidate table shape where applicable | An output-only contract cannot describe the protocol |
| TemporaryDirectory.close | Preserve the native handle on error so cleanup can be retried | Treating all close methods as unconditional consumption prevents retry APIs |
| ProcessStream.close | Clear the native handle before reporting a close error | A generic rule that every error preserves inputs would be false |
| BufferedWriter flush | Writes can make partial progress and reset buffered length on error, without necessarily ending a safe storage generation | Preserving generations must not be interpreted as preserving contents or external state |
| Independent choice outputs | Each discriminator has its own payload provenance | Restricting contracts to the first output rejects ordinary fixed signatures |
| Forwarding a reference or mapped virtual handle | Preserve actual input identity when promised | A validity dependency alone cannot identify storage for later writes or invalidation |

These observations come from the implementations, not from proposed signatures.
Native handle state and external I/O progress are protocol properties; they must
not automatically become safe-reference or acquisition facts. The first effect
implementation should describe safety-relevant ownership and generations, not
prove arbitrary resource usability predicates.

A focused local probe adapted `collections/99_hash_map_growth_failure`: capture
an entry reference before a failed growth insertion, then read it only in the
error branch. The compiler rejects that read with "reference depends on a root
that has ended". A control that reacquires the reference in that error branch
compiles and runs successfully, retaining the fixture's length, capacity, entry
contents and allocation-count checks. This confirms an observable false positive
from missing result/post-state correlation, not merely a hypothetical API need.

The existing ownership fixtures also distinguish identical return post-states
(case 210) from different return states that must be joined (case 211). This
supports retaining common guarantees and merging unrelated branch alternatives,
rather than preserving a symbolic formula for every condition in a body.

## Precision levels and costs

| Level | Coverage gained | Implementation cost and limit |
| --- | --- | --- |
| Unconditional whole-value dependencies | Simple borrowed handles | Low, but too coarse for sibling fields, variants and owning results |
| Structured fields, variants, input paths and named domains | Aggregates, nested references, domain-specific invalidation and ordinary owners | Necessary foundation; share array element templates and canonical identities rather than expanding runtime elements |
| One output discriminant controlling a complete effect set | Fallible growth, conditional transfers, retryable operations and effects on other outputs | Substantial: retain call provenance, infer exit effects after cleanup and refine caller facts |
| Nested discriminants along that payload path | Optional borrowed results inside Errable, tagged ownership alternatives | An extension of structural traversal; requires output projection selectors and parent guards |
| Input-variant guarded effects | APIs whose behavior depends on an input choice and has no corresponding returned tag | Useful later; needs specialization of the contract against input facts and proofs for unknown inputs |
| Conjunctions of independent discriminants | Joint outcomes of several outputs or independent choice fields | High cost; conjunctions, contradictions, alias interactions and potentially products of alternatives; no inspected core operation establishes a need yet |
| Numeric predicates and index relations | Capacity-sensitive preservation, exact partial progress, disjoint dynamic elements | Very high cost; approaches refinement/dependent typing and requires arithmetic and loop reasoning |

Representation of independent guarded facts can grow with the sum of the
represented alternatives; materializing combinations can grow with their
product. This describes representation size, not a complexity guarantee for
whole-program inference. Fixed-point iteration, aliases, recursive summaries and
structured effect joins still have their own costs.

## Required contract vocabulary

Keep output validity, reference identity, ownership and storage transitions
separate. A useful model needs to describe:

- Permitted dependencies of outputs and stored input/domain values.
- Required identity of returned references and forwarded handles.
- Fresh owner roles, transferred input ownership, destruction and consumption.
- Initialization and preservation of safety-relevant input state.
- Ending or replacing generations and their effects on older references.
- Hidden dependencies introduced into, or discharged from, opaque storage.
- Consumption of authenticated acquisition capabilities, independently of raw
  addresses and ordinary validity roots.

These effects should work unconditionally or under the supported outcome guard.
Do not add a separate restricted vocabulary for payload clauses. `consumes(input)` names definite destruction through a mutable reference.
`relocates(destination, source)` names exact ownership-preserving initialization
of an available destination from a mutable-reference source.
Unconditional `retains(storage, value)` permits hidden input
retention, `from_storage(output, storage)` permits hidden output provenance,
and `empties(storage)` guarantees discharge of hidden dependencies. None proves
runtime slot occupancy or exact hidden value identity. Initialization effects
and conditional hidden transitions need further modeling. Known storage inputs
and single-storage receiver domains share these effects; grouped domains and
reference mappings require more precise storage identities.

Common clauses apply to all outcomes. Conditional clauses add permissions and
obligations. An empty error clause preserves generations only when no common
clause permits their invalidation; it does not guarantee unchanged contents.

Permissions describe an upper bound on possible effects. Guarantees describe a
lower bound on facts the caller can rely on. For an inferred branch join, union
possible dependencies and invalidations, but intersect definite identity,
preservation and initialization guarantees. Never merge these categories with
one undifferentiated union operation.

## Caller and inference architecture

SafetySummary carries recursive ValueEffect outputs, input post-states,
capability uses, hidden storage effects and domain invalidations. Generation
outcomes retain their controlling output and nested payload path. Callers attach
proofs to the current generation and refine them through that result; stable
lexical forwarding preserves the relation in wrapper summaries.

Further storage dimensions must retain variant-indexed return effects,
including normal and early-return cleanup, before computing the unconditional
fallback. Adding clauses or output facts alone cannot recover correlations after
a branch join. Initializedness, ownership, capability use and cleanup must agree
on the same guard instead of postponing only generation invalidation.

Instantiate guarded effects against actual caller storage identities. Keep
output payload views separate from the authoritative input transitions. Common
unconditional consumption establishes deinitialized caller places. Conditional
consumption and whole-place relocation also retain selected caller resource
states and cleanup flags, including when the result is ignored. Extending these
effects to opaque storage must preserve that agreement.

Required behavior includes:

- Match, is-tests, payload access and error propagation select compatible facts.
- Result moves, copies and field projections preserve guard provenance when the
  represented value remains unchanged. Overwriting a result removes its ability
  to discriminate that historical call.
- Unresolved outcomes block uses that might observe invalidated or consumed
  storage. Discrimination can prove that a generation survived a particular
  call; it cannot restore a generation ended by an intervening operation.
- Refinement never restores a snapshot of caller state. Later writes, cleanup,
  invalidations and capability consumption remain effective.
- Input aliases are resolved before interpreting effects. Overlapping domain
  targets cannot gain independent preservation guarantees; conflicting precise
  post-values require a conservative join or a conformance diagnostic.
- Wrapper summaries retain the relation between their returned variant and the
  underlying call effects. A contract that works only immediately after a call
  is insufficient for ordinary library composition.
- Multiple independent guards affecting the same fact use conservative marginals.
  Do not combine singleton guarantees into a conjunction that was never proved.

For loop-carried call results, merge differing call occurrences and storage
versions conservatively. Recursive summaries use canonical input paths/domains
and finite shared structural templates; do not append an unbounded history of
call instances to persisted summaries.

## Conservative loss of detail

When a relation crosses the structural boundary:

- Union possible validity dependencies, hidden retention and invalidations.
- Preserve a known alias only when all remaining alternatives agree.
- Keep possibly consumed resources and capabilities unavailable for operations
  requiring definite availability. Preserve consumption conflicts.
- Preserve ownership obligations and fresh root roles; unknown correlation is
  not permission to drop an owner, free twice or manufacture a resource.
- Intersect guaranteed empty/initialized/preserved post-state facts.
- Reject a proof obligation if no sound representable upper approximation exists.

A loss of precision can reject a valid implementation or require reacquiring a
reference. Diagnostics should distinguish that limitation from an observed
violation and point to the relation that could not be proved. Never certify an
explicit contract using only a weakened inferred summary that omits effects.

## Acceptance cases before broadening the syntax

The next implementation should pass paired positive/negative cases for:

1. Reserve failure retains a pre-call reference; success invalidates it, including
   through a forwarding wrapper and error propagation.
2. Invalidation through an aliased input defeats an apparent sibling preservation
   guarantee. Truly separate domains remain independent.
3. A later unconditional invalidation cannot be undone by testing an older result.
   The same applies to later capability consumption and result overwrites.
4. A fallible transfer returns its owner on one variant and stores it on another;
   cleanup occurs exactly once on every path, including ignored results.
5. Error variants carry tracer dependencies without adding them to successful
   scalar payloads; nested optional borrowed payloads retain their actual domain.
6. One output variant governs a second output's provenance; callers cannot use
   the second output's stronger facts before testing the controlling tag.
7. Independent output conditions lose joint correlations conservatively. A
   contract that requires their conjunction reports an unsupported proof.
8. Dynamic indexing uses a shared element abstraction; static sibling fields
   preserve independent facts without claiming dynamic element disjointness.
9. Different owning roots on recursive/loop paths do not create unbounded summary
   histories or become fresh acquisition capabilities at an erased call.

Use these cases to decide further precision. Do not add multi-discriminant logic
or arithmetic predicates merely because the syntax can express them.

## External comparisons

Rust's Vec::try_reserve documents preservation of contents on failure. That is an
API behavior, not evidence that Rust permits keeping a safe reference across its
mutable call. Argi's generation-based model needs its own checked contract for
such uses:
https://doc.rust-lang.org/std/vec/struct.Vec.html#method.try_reserve

Polonius documents the precision/performance trade-off of location-insensitive
loan propagation versus CFG-sensitive propagation. Its model is not Argi's
ownership model; the relevant lesson is that erasing control-flow correlations
can create false positives and that recovering them requires work in the checker,
not only richer signatures:
https://rust-lang.github.io/polonius/rules/loans.html

## Development order

1. Extend forwarding to branch-assigned intermediate results, error propagation
   and choice tests on computed expressions. Keep conservative fallback for
   unproven relations and output slots that may be rewritten.
2. Extend hidden retention and extraction with exact ownership identities and
   checked initialization effects. Extend
   existing conditional known-input consumption and relocation to erased storage
   only with representable post-values and cleanup identities, keeping resource
   state and cleanup correlated with the selected outcome.
3. Measure representation growth and reevaluations using core-sized examples;
   retain selective structural partitions rather than products of independent
   output discriminants.
4. Reconsider input guards and joint discriminants only when a concrete useful
   API remains unnecessarily rejected by the structural boundary.
