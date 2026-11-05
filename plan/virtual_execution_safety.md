# Virtual resources and execution safety

## Status and scope

Implementation investigation for 0.5, not an implemented language guarantee or
runtime ABI. [The resource authority core](resource_authority.md) defines the
proposed shared rules and minimal implementation gate. Resolve this note's
concrete gaps within that model before extending owning task transfer or
introducing dynamic conformance lookup. The current boundary remains in
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

The common rules for contract roles, instance bindings and result post-relations
are defined in [the core model](resource_authority.md#contract-relations-and-instance-bindings).
The implementation must reuse ordinary output-summary relations; no Virtual-only
permission model is proposed.

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

Deferred exploration, outside the current 0.5 core gate.

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
| `InputPath`, `InputAccess`, `GlobalAccess`, `unknown_access` | Caller-relative may-access bounds | Unknown-call authorization; ordered effects deferred |
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

The completion-order gap is now closed conservatively: summary may-access
bounds are checked against entry authority before final completion is applied.
Regression cases 73X and 74X reject both orderings while the loan is pending;
case 75 verifies completion in a previous call restores entry authority. No
transition-relative effect representation has been introduced. Keep that simple
rule until a useful case justifies more precise ordering evidence.

The unknown erased-call case remains an authorization gap. Close it through
general access rules and a specified native boundary before widening the payload
or runtime subset. These probes are not supported concurrent programs or
performance tests.

## Conditional alias obligations across execution-producing helpers

A build-only probe found that distinct symbolic input identities were treated as
independent when a helper started a worker through one input and accessed the
same storage through another. Caller aliasing made the accepted program racy;
it was not executed.

The temporal checker now derives conditional alias obligations using the same
body visitor and execution identities as ordinary safety checking. Only bodies
that can reach the general lending primitive need this collection step. Reference
leaves retain entry-relative source paths; projected unknown pointees derive
their coordinates from those roots. The existing summary alias relation carries
the resulting concurrent-access obligations through the fixed point, including
wrappers and guarded effects, before final checking and cache publication. This
is not a second temporal interpreter. Collection publishes no body proof or
codegen annotations.

Cases 96X–106 cover caller aliasing, disjoint inputs, shared reads, completion
before access, independent completion of multiple receipts, copied record
references, union overlap and rejection at virtual erasure. The same obligation cannot be hidden by a callback signature. The
unknown erased-call gap remains separate and open.

## Next boundary: unknown calls

CFunction declarations now accept `reads`, `writes` and `no_access` through
`where` and the existing contract parser and summary coordinates. Argi bodies
are checked; imports retain their explicit FFI permission and audited assumptions.
The metadata grants no lifecycle transitions or output validity. Native write
bounds reject reference-bearing or erased selected storage until reference
clobbering has a sound representation. Imports currently require direct reference
regions or structural subfields; stored-reference traversal remains rejected until
its liveness requirements can be instantiated without guessing pointee identity.
This is a static boundary with no runtime
table change; it does not yet close unbounded erased calls.

Prefer reuse of existing access clauses over new flags or executor-specific
exceptions. An audited foreign declaration needs an explicit bound; its FFI
permission alone does not prove absence of interference. Such a bound is an
assumption about native code, unlike a bound checked against an Argi body. Keep
that distinction explicit and do not grant ownership, reference validity or
synchronization merely by declaring an access bound.

The native task-buffer adapter now receives its source as &Any instead of an
integer address and declares its synchronous read. Its C signature uses const
void*. Join and destruction declare no ordinary access to caller storage; they
operate on private runtime buffers, while the worker's accesses remain attached
to the execution receipt. These audited bounds do not certify completion by
themselves. The checked adapter still guarantees buffer sizes, callback pairing,
exactly-once ownership and completion before reclaiming storage.

The shared primitive registry now separates ordinary memory accesses from
ownership transitions. Reference construction and metadata-only transitions
have closed empty access sets; moving representations requires write authority
over the consumed and initialized slots. Both direct primitive calls and inferred
wrappers preserve these requirements. Allocation companion effects, raw-address
operations and latent cleanup remain unknown rather than claiming a closed set.
Regression cases 79X–82X and 86X reject direct and wrapped primitive access to
pending loans, 83 permits reference projection under no_access while a writer
is pending, and 84X–85X check that move and latent
cleanup requirements cannot disappear behind virtual bounds.

Before closing an executor interface's bound, check delegation through captured
virtual capabilities. A bound on the receiver's ordinary fields does not authorize
all captured referents. Any general rule for selecting a nested virtual's regions
must agree between conformance checking and call-site authorization; recognizing
an executor implementation or just inspecting its method table is insufficient.

## Delegated virtual receivers

A named access mapping to a Virtual field denotes that value's erased receiver,
while locating the handle requires a read of its slot. Verification and caller
instantiation use the same receiver-domain coordinate. A contract bound must
match both the region identity and the complete handle path; a bound on handle
bytes or on a sibling field grants no access to the erased receiver.

This composes existing receiver bounds through a wrapper without expanding the
runtime representation or inspecting the selected implementation. Tests 87–93
cover exclusive access, shared reading, factory returns and rejection of sibling
handles, handle-only bounds and unmentioned captured domains. A mapping to a
virtual receiver does not include that virtual's named captured regions. Exact
selection and transport of those regions remains necessary before closing a
general delegated executor bound.

Addressed input subobjects retain their complete projection when collecting
accesses; following their address neither invents an unknown access nor widens a
field write to its whole parent. Global alternatives remain separately tracked.
Tests 94 and 95X cover an independent sibling loan and a possible global alias.

## Symbolic captured domains

A domain of an unknown virtual value needs an interned symbolic storage identity,
keyed by the observed handle and its generation. It is not an embedded byte
projection, an acquired reference or a disjointness proof. Copies preserve the
identity; replacing the handle observes another incarnation. Named regions keep
their own generations so invalidating one does not automatically consume the
handle or another region.

All consumers must preserve symbolic targets alongside concrete Places: access,
caller alias obligations, lifetime capture, invalidation and evidence forwarding.
An operation requiring a concrete opaque storage identity must reject missing
evidence, never silently discard its symbolic obligations. Conditional generation
proofs must either represent the symbolic transition or retain a conservative
invalidation until that representation exists.

The checker now interns captured-domain observations in the same symbolic-storage
namespace as projected input observations, using a distinct selector. Opaque
storage provenance and conditional generation proofs can name either a concrete
Place or a symbolic identity. Neither representation grants a data address,
reference validity or acquisition evidence. Domain containment deliberately does
not make a captured region part of the handle's embedded storage.

Regressions cover nested virtual inputs by value and by reference, aliased versus
independent concurrent arguments, stale views after domain invalidation, and
continued use of an independent domain (concurrency 107–110 and polymorphism
351–354X). Conditional failure preserves the matching current generation; success
does not revive an earlier view. Existing generic opaque put/take wrappers
exercise retention and extraction without fabricated pointee Places. Captured
hidden referents remain dependencies even after their container is emptied;
returning a borrowed container cannot hide a local referent. Function-exit
validation also checks caller-relative opaque domains without requiring an output
value (ownership 404X); a helper cannot leave a local borrow hidden in its caller's
collection. This does
not enable owning task payloads, execution affinity, arbitrary symbolic capture
traversals or correlated heterogeneous cleanup requirements.

## Decisions required before implementation

1. Specify the shared representation of indirect operation requirements and
   latent cleanup effects in safety summaries and virtual contracts, including
   unknown effects. Keep conservative call-entry requirements; general ordered
   effects are outside the current design gate.
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


## Layout-aware overlap

Access authority must follow physical overlap without merging logical storage
identities. Distinct record fields can be independent, but CUnion alternatives
occupy overlapping storage. The shared overlap query now consults the selected
container layout, including nested unions, for both pending loans and ownership
alias checks. Unknown layouts remain conservative. Regression cases 76X–78X
and C interop 158X reject overlapping ordinary writes, second task loans and
bounded native writes; the native access fixture retains a positive independent
record-field case.

## Next checkpoint: unknown call authorization

The unknown erased-call authorization gap remains open. An experiment rejected
all summaries with `unknown_access` while any execution retained a storage loan.
It also rejected valid `await` paths: native result-buffer references currently
carry lifetime evidence without an authenticated access-region identity. The
blanket rejection is not enabled. An attempted submission bound using
`writes(self)` and `reads(request._input)` accepted an embedded provider but
rejected the existing reference-based forwarding executor. Provider representation
and captured provider storage are different regions. Publish a relational bound
before closing that interface; do not silently widen `self` to all captures.

Composition excludes writes to local by-value argument slots while retaining
effects through reference leaves. Alias obligations substitute storage coordinates
rather than mere lifetime sources, preserving exact referents through wrappers.

Before enforcing the rule, represent those accesses using general opaque storage
and provenance rules. Do not infer containment from a lifetime anchor or exempt
`Future`/`Executor` by name. Native imports retain their audited FFI assumptions;
Argi implementations must prove their bounds. A completion postcondition alone
cannot authorize unknown accesses that may occur earlier in the call.

Regression cases 111–114 cover mutation of local argument copies under
`no_access`, rejected external reference writes, rejected possible module aliases,
and a stateful executor that delegates to an embedded provider. The result-buffer
provenance problem remains separate: lifetime dependence alone must not be
reinterpreted as ownership, containment or independent access authority.

## Existing whole-value relations

The proposed relational core does not require a new clause for exact forwarding.
`transfers(result, source)` already carries the entire value through a virtual
method's output summary, including nested `Virtual` domain facts. Generic cases
116 and 117X verify that a returned record retains shared-read compatibility and
write conflicts with the original referent's pending loan. Cases 118X and 119X
reject lifetime-only publication and returning a different input, respectively.
No new authority, acquisition proof or runtime witness is introduced. Cases
120X and 121 contrast heterogeneous extraction without a usable region identity
against a common verified `no_access` contract, using different provider types.
The latter is not a general certificate for arbitrary methods on stored values.

This does not express every factory relation. A capability newly constructed from
a provider, or a published subset of its captured roles, still needs sufficient
verified post-relations. Do not equate that missing case with whole-value transfer
or weaken `depends_on` to recover it.

## Minimal next relation: delegation through named roles

The next missing case is a wrapper whose operation delegates to a named region
of a captured virtual capability. Mapping to the handle's bytes or only its
implicit receiver is insufficient. Conceptually, an outer role must be able to
select the captured occurrence and then one of that occurrence's contract roles,
for example `outer.state = self.base.state`. This is a required semantic relation,
not a claim that the current mapping parser accepts that path.

Prefer extending the existing region-selector representation over introducing a
new safety system or universal transfer marker. `InputPath` already separates
structural projections from a terminal `storage_domain`; `InputDomain`,
`OutputDomainEffect` and instance `DomainFacts` supply the other existing pieces.
The implementation mapping must preserve the selected contract and occurrence;
equal numeric domain indices from unrelated contracts are not identity evidence.
A nested role is a selection of the captured virtual's public binding, not
permission to inspect its concrete implementation or all its lifetime dependencies.

A valid implementation proves the delegated method's instantiated requirements
fit that selected outer role. Forwarding must preserve this relation across
copies, generic helpers and retargeting checks. Missing or stale binding evidence
stays unknown. No vtable descriptor, ordered-effect graph or native promise is
needed for this relation.

Before implementation, cover direct and nested delegation, unrelated role names
or occurrences, reference retargeting, and static-versus-erased producer results.
This extension would not by itself express every new result-region postcondition
or make an unknown native address an owned region. Keep those requirements
separate and reuse the same selectors when an actual gate case needs them.


## Minimal unknown-call reproduction

After the associated-region migration, a compile-only probe still accepts an
unbounded virtual read while a worker holds write authority over the same Int32.
The contract declares `.get: (.self: &Provider) -> (.result: Int32) where {}`;
its Int32 implementation returns `self&`. Construct the handle from `&value`,
start a worker with `$&value`, then call `get(&handle)` before completion.
Making the observed result affect control flow does not change acceptance.
The corresponding `reads(self)` bound correctly rejects the call. Do not run the
unbounded probe: compilation is the evidence of the missing authorization check.

This case requires no owner transfer, raw address or heterogeneous extraction.
It confirms that unknown-call authorization is an independent soundness gate,
not merely a precision improvement for future resource types. Closing it still
requires preserving valid join/result-buffer access and executor delegation;
the native consolidation below does not discharge that gate.

## Native buffer boundary consolidation

The private native task ABI now has one lifecycle: create stable aligned input
and output buffers, invoke the monomorphic callback once, join before extracting
the result once, and join before reclaiming both buffers. Removed the unused
handle-callback protocol and its separate read, write and copy-out operations;
only the native probe still used them. There is no separate completion flag:
successful join proves that the sole callback returned and published its output.
The callback must initialize its complete output before returning.

The native probe exercises the same path as async, including mismatched result
sizes before completion, copied inputs, zero-sized aligned buffers, moving the
handle, independently live result buffers and destruction of a running task.
This reduces the audited native surface; it does not grant access-region
provenance to a returned address or close unknown-call authorization. Those
remain prerequisites for general owner transfer. No runtime strategy or new
compiler primitive is introduced by this consolidation.
