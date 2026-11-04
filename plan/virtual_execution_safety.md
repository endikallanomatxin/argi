# Virtual resources and execution safety

## Status and scope

Design proposal for 0.5, not an implemented language guarantee or runtime ABI.
Resolve these rules before extending owning task transfer or introducing dynamic
conformance lookup. The current boundary remains in
[the concurrency specification](../description/173_concurrency.md); broader work
is tracked in [the concurrency plan](concurrency.md).

Preserve mutable aliasing within one execution domain. Do not introduce a
Rust-style pair of type-wide transfer/sharing markers as the complete model.
Contracts may express reusable guarantees, but authorization also depends on the
actual value, its aliases, captured resources and destination execution.

The rules must apply to ordinary resources. Allocator, String, Future and Executor
are design examples, not compiler-recognized exceptions.

## Distinct properties

| Property | Question | Does not establish |
| --- | --- | --- |
| Transfer | Can responsibility and the required authority move to another execution? | Simultaneous access or unrestricted migration between physical threads |
| Concurrent operation | Can this operation overlap other specified operations on the same region under a verified protocol? | Object lifetime, safe destruction, or concurrency of other methods |
| Cleanup | Where, under which authority and by which owner can destruction occur? | Permission to mutate or share the payload |

These properties supplement validity and ownership; they do not replace them.
An unsynchronized provider may be usable after exclusive transfer if its execution
requirements permit it. A provider may support concurrent release without
supporting concurrent allocation. A payload may be readable elsewhere while its
cleanup must return to the originating domain.

Neither a readonly handle nor a lifetime dependency proves any of these execution
guarantees. A readonly method can still follow a mutable captured reference.

## Operation obligations

Describe an operation by a conservative bound on:

- Accessed regions, including indirect captures, and the required access mode.
- Execution restrictions, including affinity and permitted migration.
- Synchronization preconditions and the publication guaranteed by its transitions.
- Retained resources, latent operations and responsibilities created or discharged.

The same description applies to selected cleanup as to an explicit function call.
Infer effects through ordinary calls and verify implementations against their
contracts. A closed access bound such as `writes(self.state)` describes reachable
storage; it does not certify synchronization or execution on another thread.
Unknown effects remain unknown across erasure, recursion and foreign calls.

Do not equate a resource's lifetime dependency graph with its access-region graph.
Two independent allocations can depend on one provider. Access to their bytes
need not conflict, while their destructors may conflict through that provider.
Keep those relationships separate and retain the latent operation's connection to
its exact captured capability.

## Authorization rules

A candidate judgment is:

```text
validity facts; authority and obligations |- operation(value) @ domain
    -> updated validity facts; authority and obligations
```

It is valid only when:

1. Every selected resource and observation is live in the required generation.
2. Every possible ordinary access has compatible authority. Overlapping accesses
   from potentially concurrent domains conflict if either requires writing.
3. The operation's execution and synchronization requirements are satisfied.
4. Every retained or newly created obligation has a responsible owner on every
   returning path. Authority and cleanup responsibility cannot be duplicated or
   silently discarded.
5. Every discharged obligation has matching verified transition evidence.
   Completion must identify the execution and storage incarnation, and establish
   publication before permissions or results are recovered.

Multiple mutable aliases in one domain share its authority. Certified
serialization or synchronization can supply a different access protocol, but
sharing an executor alone supplies neither. The checker must not infer arbitrary
lock-free correctness from the presence of atomics.

A handoff must specify the destination's permitted operations and a cleanup plan.
Check the transitive resources those operations require, including permitted
failure and cancellation cleanup. Do not require cleanup in the destination if a
verified protocol retains that responsibility elsewhere. Such delegation must
retain the resource until all users finish; simply dropping an observer is not
completion.

## Binding effects to resources

Use the following abstract record to discuss an operation; these are semantic
components, not proposed source keywords or a chosen serialized representation:

```text
Effect = (MayAccess, ExecutionRequirements, RetainedObligations, MustTransitions)
```

`MayAccess` is an upper bound on accesses during the operation, not just its final
writes. `MustTransitions` states what holds on every selected returning path.
Keeping these components independent prevents a postcondition from erasing a
memory effect or making an unknown execution requirement appear satisfied.

A region selector is rooted at an ordinary input, a captured capability or an
identified global. Field selection and reference traversal are different steps.
Bind a named contract region through the selected implementation mapping; do not
interpret its local numeric index as an identity shared by unrelated contracts or
instances. Equal names do not prove aliasing, and distinct selectors do not prove
nonoverlap. Instantiation resolves them to known storage or conservative symbolic
regions, with the necessary generation and traversal evidence.

For a latent call, retain the relation:

```text
(owner occurrence, selected operation, captured capability selector,
 operation requirements, relevant generation and cleanup responsibility)
```

The same selected destructor can therefore have different instantiated effects
for different values. Its summary can refer to an operation on a captured virtual
capability without knowing that capability's implementation. This is a required
semantic relation, not a proposal to store another callback in every value.

For example, cleanup of an owner containing an erased release capability has a
latent requirement to invoke that capability's release operation. Reading the
owner's payload does not itself invoke release. A handoff must nevertheless retain
a valid cleanup plan for every path where release may become necessary. The
capability's contract or additional verified evidence must provide the required
bound; merely recording an unresolved latent call does not discharge it.

Substitution must preserve the owner-to-capture relationship through ordinary
calls, record fields, moves and erasure. A dependency on the capability's lifetime
cannot stand in for the operation requirement. Requirements conditional on another
captured capability remain conditional until that instance supplies the evidence.

### Unknown effects

Distinguish a known empty effect from an unknown effect. An unresolved selector is
not an empty region; an unbounded call is not `no_access`. A readonly input or the
absence of visible writes in a wrapper does not close a transitive effect bound.
The existing `unknown_access` bit has no region scope and cannot establish that a
call avoids a pending loan.

In a context with potentially concurrent accesses, an unknown effect must be
checked conservatively against every region it may reach. Narrowing its scope
requires verified bounds, not a heuristic based on the visible argument layout.
Unknown execution requirements likewise cannot establish portability even if the
memory-access bound is known empty.

Sequential unknown calls remain subject to existing validity and foreign-boundary
rules. Extending concurrency requires a principled account of native start, join
and other operations as well: do not exempt them because their names or modules
belong to a bundled executor. A future audited boundary must explain both its
access bound and the transition it certifies.

### Temporal composition

An operation's final completion guarantee does not authorize all accesses in its
body using the resulting authority. These two bodies have different obligations:

```text
write(region); certify_completion(receipt)
certify_completion(receipt); write(region)
```

Absent an ordering proof, check the may-access bound against entry authority.
To admit the second ordering when entry authority is insufficient, a summary must
preserve that the matching certified transition precedes that access on every
applicable path. The proof must name the same execution, region and generation;
completion of a different receipt cannot satisfy it.

This is a general requirement for authority-changing transitions, including guard
acquisition, publication and cleanup delegation. Do not add a special after-await
exception. Accesses may require entry authority or authority established by a
verified predecessor transition. A final post-value alone proves neither.

At branch joins, retain every possible access and only those ordering/transition
guarantees established on all relevant paths. Outcome-specific evidence may refine
the selected path. Loops need a finite conservative fixed point, not an unbounded
expansion of event histories. When ordering is unresolved, retain the entry
requirement rather than assuming a favorable order.

Apply the same rule to opaque retention. A completion postcondition cannot justify
losing a pending receipt before completion. Conversely, a proven prior completion
can permit retaining the already completed value. The current conservative
retention filters must remain until that distinction can be represented.

## Three sources of evidence

| Source | Can establish | Cannot establish alone |
| --- | --- | --- |
| Static contract guarantees | Requirements and bounds valid for every conforming implementation, available even for an unknown erased value | Stronger optional behavior of one implementation, current exclusive authority, or an instance's originating domain |
| Contextual checker evidence | Actual region identities, generations, aliases, exclusive handoff, retained dependencies and completion obligations | An undocumented guarantee of an unknown implementation or an arbitrary native synchronization protocol |
| Dynamic implementation evidence | A verified additional conformance discovered after erasure, if a representation and acquisition protocol are provided | Liveness, authority, per-instance affinity, or guarantees of separately captured providers |

Combine evidence rather than replacing one source with another. The compiler may
use concrete knowledge at construction, but that knowledge is useful only if its
relevant evidence survives calls, moves and erasure. An API receiving an unrelated
erased value must rely on its contract and retained evidence, not rediscover the
concrete implementation by specialization.

Static contracts plus contextual evidence can already describe an exclusively
transferred portable provider without a concurrent-operation guarantee. They can
also support a uniformly stronger virtual interface. They cannot recover an
optional guarantee that an unknown producer erased and did not retain.

Dynamic evidence is a candidate for that last case, not a prerequisite for every
virtual call. Alternatives include preserving stronger static evidence at the
producer or returning a separately checked capability. Compare the ergonomics,
representation and compatibility costs against the acceptance cases before
choosing a descriptor design.

## Erasure and heterogeneous storage

Virtual must retain the safety meaning of its interface. Its method table is not
permission to forget effects or captured resource requirements. An owner containing
a virtual capability must retain its latent obligations even when its own nominal
type does not mention the concrete provider.

For an erased value, preserve correlations between each possible implementation,
its captured region identities and its operation requirements. A join may retain
conservative alternatives. Authorization must cover every feasible alternative
unless checked evidence narrows them. Never combine one alternative's concurrency
guarantee with another's provider identity.

Collections make this requirement observable. Extracting an element must recover
evidence for that element and generation, or a sound set of possible elements.
A container-wide union of lifetime roots cannot recover an exact receipt, invent
access authority or select the most permissive implementation. Completing one
extracted task cannot complete its siblings.

Replacement must retire or re-establish evidence for the replaced value. A proof
for one element is not a proof for the entire collection. An all-elements proof
needs a membership/shape invariant and checked insertion and replacement rules.
Conservative rejection is acceptable when these relations cannot be represented.

## Candidate dynamic acquisition boundary

Keep `Virtual` as two pointers while possible. Do not add runtime flags,
descriptors, a third handle pointer or new trusted operations at this stage.

If additional dynamic evidence proves necessary, acquisition should be explicit
and potentially fallible. An implementation-wide witness must be verified for
all instances sharing it. State-dependent guarantees need separate instance
conditions. Thread identity and captured-provider authority are not properties of
a shared method table. A wrapper delegating to an unknown captured service
cannot publish an unconditional guarantee merely because its own body has no
local writes. A witness can instead express a verified requirement on that
service; acquisition must also establish the instance's captured evidence.

A successful acquisition would bind the guarantee to the relevant virtual value,
implementation and captures. Moving that value preserves the relationship;
retargeting captures, replacement or incompatible context changes require
revalidation. A copyable conformance fact does not duplicate exclusive authority
or cleanup ownership. Those obligations retain their own conservation rules.

Subsequent calls can use the retained proof without automatically repeating a
runtime conformance query. Their validity, authority and execution preconditions
still apply. In particular, a concurrent method is not permission to destroy its
receiver while another execution uses it. A dynamic witness also cannot certify
an arbitrary FFI body: the underlying protocol needs a verified implementation or
an explicitly justified audited native boundary.

## String as a design test

Use a heterogeneous collection of String values with virtual deallocators as an
acceptance test for the general rules. This does not propose String-specific
annotations, transfer operations or runtime checks. The same outcomes must follow
for a user-defined owner retaining an erased cleanup capability.

| Case | Required outcome |
| --- | --- |
| Isolated payload; portable provider with a verified concurrent release operation | Transfer may proceed if lifetime and the remaining operation requirements hold |
| Isolated payload; portable unsynchronized provider transferred exclusively | May proceed while every incompatible provider access is unavailable |
| Same provider remains in incompatible use by the caller | Reject despite isolated payload ownership |
| Cleanup is affine to the originating domain | Reject worker-side destruction; permit delegation only with a verified cleanup owner and completion protocol |
| Provider permits concurrent release but not concurrent allocation | Release guarantee does not authorize allocation |
| Unknown erased provider, without sufficient static or contextual evidence | Reject the requested operation; a future explicit acquisition may succeed or fail |
| Two payloads alias mutable bytes, despite strong deallocator guarantees | Reject incompatible payload access |
| Extracted element has several possible deallocators | Check all alternatives, or narrow them using retained verified evidence |
| One element passes an additional guarantee check | Preserve the proof for that element; do not strengthen its siblings |
| Element replacement or a changed captured provider | Do not apply the former value's proof to the replacement |
| Failure or cancellation before worker completion | Preserve cleanup responsibility and outstanding authority obligations |

Include provider aliases hidden in other elements, returned collections, nested
owners and cleanup-only accesses. The selected element's nominal type and the
vtable's implementation identity alone are insufficient answers.

## Implementation map and confirmed gaps

| Existing mechanism | Reuse | Missing information |
| --- | --- | --- |
| `InputPath`, `InputAccess`, `GlobalAccess`, `unknown_access` | Caller-relative may-access bounds | Scoped unknown effects and transition-relative access requirements |
| `DomainFacts`, symbolic pointees and `RegionTraversal` | Captured region and traversal identities | General symbolic/opaque extraction with correlated alternatives |
| `ValueEffect` dependencies and domain effects | Substitution through values and calls | Latent operation requirements bound to the retained capability occurrence |
| Selected `Deinit` evidence and cleanup flags | Cleanup selection and unique responsibility, including indirect moves | Execution requirements of latent cleanup and delegated responsibility |
| Execution receipts and `completed_executions` | Exact pending identity and final completion guarantees | Ordering between completion, accesses and retention |

A build-only investigation at `b5f23c664` confirmed two currently accepted cases
that the general rules must reject. They were not executed:

- An unbounded contract setter, `where {}`, writes a captured mutable reference.
  A wrapper taking only `Virtual#(Contract)` invokes it while a worker has a read
  loan of that referent. An unknown access summary does not currently prevent
  that caller-side conflict. Existing worker-side isolation restrictions do not
  establish safety for arbitrary operations executed by the caller.
- A wrapper writes through an input reference and only then awaits a future whose
  worker borrows that referent. Its completion is applied before its access bound
  is checked at the caller, admitting an earlier incompatible write.

The second probe's distinguishing body is:

```rg
finish_after_write := (.future: $&Future#(Int32), .value: $&Int32) -> () {
    value& = 7
    _ = unwrap_or_abort(.value = await(future))
}
```

Calling it with a pending future reading `value` must fail. Reversing the two
statements is semantically safe only with a proven ordering; a conservative
implementation may reject both until it has that evidence. Neither case requires
any dynamic conformance machinery to expose the problem.

These are safety gaps, not supported concurrent programs or performance tests.
Close them through general access authorization and transition rules, while
specifying the native boundary, before widening the payload or runtime subset.

## Decisions required before implementation

1. Specify the shared representation of indirect operation requirements and
   latent cleanup effects in safety summaries and virtual contracts, including
   unknown effects and transition-relative access requirements.
2. Specify how erased and opaque values conserve correlated region, generation,
   execution and cleanup evidence, including joins and extraction.
3. Apply those rules to the matrix above, first using static contracts and
   contextual evidence. Identify exactly which remaining cases need a dynamic
   query rather than a stronger producer-side contract.
4. Only then compare concrete dynamic witness representations and their costs.
   Any trusted transition must state what it authenticates and why existing
   verified operations cannot establish that fact.

Do not broaden task payload eligibility or remove conservative opaque-retention
checks until these rules can justify the new cases without names specific to a
library abstraction.
