# Resource authority design experiment

## Executable authority experiment

Run `python3 tools/resource_authority_model.py`. This independent design model
checks a deliberately bounded authority fragment: one two-byte allocation,
three logical executions, initially read/write or readonly grants, overlapping
region selections, two nonreused loan identities, nested lending and completion.
It is not compiler code, a proposed runtime representation or a proof of the
complete Resource Machine. The ordinary compiler suites do not execute it.

The depth-five exploration reaches 768 states through 948 accepted transitions.
Each accepted state checks exclusive writers, compatible readers, no authority
stronger than the source grant, and live observations for pending loans. Explicit
adversarial traces additionally check wrong/duplicate receipts, absent publication,
unfinished execution, stale generations, partial restoration, disjoint writes and
rejection of invalidation during outstanding use. These counts describe this
model and bound only; they say nothing about compiler correctness.

The model derives current authority from original grants and outstanding loans,
not from restoring an unconditional write flag on completion. Readonly origins
stay readonly, completing one reader leaves other readers effective, and
nonoverlapping bytes can recover authority independently. Byte selections are
finite sets here, so symbolic alias uncertainty and C layouts are not modeled.

A nested loan exposes an additional conservation requirement: worker quiescence
is insufficient to discharge its borrowed authority while a child still retains
it. This experiment rejects parent completion until child obligations discharge.
A later protocol could instead explicitly transfer those obligations to another
responsible holder; merely forgetting the parent receipt cannot do so.

The loan exploration does not model ownership/cleanup, protected protocols,
physical acquisition, arbitrary regions, several inputs per execution, summary
inference, control-flow joins, failure unwinding or weak-memory implementation.
The separate contrasts below address only bounded fragments of those questions. Extend the
small semantics only when a concrete counterexample requires another fundamental
relation. In particular, do not treat these successful checks as evidence that
the unknown-call or native-buffer gaps in develop have been closed.

### Physical membership contrasts

`AuthenticatedExtent` is an explicit oracle hypothesis about physical bytes;
`StorageObservation` records possible selected regions and a generation. Neither
creates grants in the existing `State`. Bounded selections reject out-of-range
requests, and access checks every retained alternative against that same state's
authority. Distinct receipt identities do not imply disjoint storage. An empty
list of possible backings represents missing evidence and is rejected, while a
known zero-sized selection is an explicitly empty physical region.

The experiment includes 48 checks that widening backing alternatives cannot
turn a rejected precise access into an accepted one. Adversarial examples cover
stale generations, overlapping extents, unavailable bytes despite successful
range validation, and loading an erased handle before a `no_access` method.
Lifetime anchors and cleanup ownership provide no constructor for an extent in
this experiment.

This does not solve abstract factory results. The oracle supplies actual byte
coordinates and assumes the extent is authenticated. The compiler still needs
a verified contract relation that preserves physical membership through ordinary
summaries, erasure and suballocation. Deriving that relation from a nominal owner
or its lifetime dependency would bypass the very property under investigation.

### Sealed storage and frame erasure candidate

The experiment now contrasts a valid older storage observation with a later
independent lexical allocation. Erasing its exact backing within the older
allocation frame permits access under a loan of the later byte, but still
rejects a loan of its possible older backing. Subviews retain their possible
backing instead of receiving physical freshness from a new identity.

`erase_in_frame` checks its supplied frame against the concrete oracle regions
before widening. It performs 72 conservative erasure checks over valid source/
frame combinations. An adversarial example inserts a later reference into an
older container: using the container's old frame is rejected because it excludes
the value's real backing. Joining the old and inserted values must retain that
possible alias.

These are checks of a proposed abstraction against an explicit oracle, not a
model of stack allocation or a proof of the allocation/frame theorem. Allocation
identity is assumed in the supplied frame; it is not reconstructed from timestamps
or lifetime roots. The compiler has not implemented sealed type invariants or
this frame abstraction. Its cost and its interaction with mutation/opaque storage
must be justified before adopting it.

### Physical backing, owner observations and address reuse

`PhysicalHeap` adds a separate bounded oracle for allocation identity, byte
ranges and owner generations. It checks 900 pairs of valid views against explicit
byte-set overlap. Views with different owners can alias the same backing;
subviews restrict a parent range instead of creating an independent allocation.
Resetting an owner invalidates its old views without freeing the backing or
invalidating views tied to another still-valid owner. Releasing backing invalidates
all its views, and reacquiring the same address uses a different nonreused identity.

This strengthens the earlier frame experiment's assumptions: a publication frame
must contain allocation identities, not numeric addresses. Otherwise an old frame
could accidentally appear to cover newly acquired storage at a reused address.
The overlap oracle works on addresses only after validating each view's backing
and owner generation. New view/owner identities supply no disjointness evidence.
`PhysicalFrame` bounds unknown backing by allocation identities. Its erasure
operation requires the actual validated view to lie within that frame; overlap
answers are conservative for all 900 view pairs. Fresh later backing can be
excluded, but an overlapping alias of existing backing cannot. Publishing a
later view with an old container's frame is rejected; widening the value's frame
retains the possible conflict. Validation occurs before checking frame membership,
so neither an expired view nor newly acquired bytes at an old address inherit an
old proof.

Allocation is still an oracle that rejects overlapping live backing; the checker
has not proved that an arbitrary allocator satisfies it. `release` and owner reset
also assume that outstanding users have already been discharged. This fragment
does not model concurrent deallocation, physical slot acquisition in the compiler,
zero-sized object ownership, alignment, abstract factory contracts or weak-memory
publication. It neither grants authority nor replaces the existing loan experiment.

The representation is informed by [Low*'s buffer and modifies model](https://fstarlang.github.io/lowstar/html/LowStar.html),
which separates buffer slices, liveness, disjointness and framed modifications.
Argi does not adopt its general refinement/proof language. These experiments test
our proposed distinction, not the correctness of Low* or an equivalence with it.

### Resource-transformer reference cases

The same experiment includes a finite reference interpreter for access,
certified completion and failed completion. Explicit path alternatives are an
oracle for testing candidate summary abstractions, not the proposed production
summary representation. The compiler must not enumerate arbitrary execution
traces as its solution to composition.

The reference cases distinguish:

- Completion followed by access from access followed by completion, despite
  identical unordered access/completion sets.
- Completion of the matching receipt from completion of another task's receipt.
- Successful completion from a failed attempt that leaves authority suspended.
- A branch that returns an outstanding obligation from a branch that discharges
  it. A later unconditional access must satisfy both possible returning states.
- A precise input from erased alternatives: adding a potentially conflicting
  alternative can only restrict a call, never grant authority.
- An unknown-footprint operation after one completion from that operation after
  every relevant loan has been discharged.

A call is accepted only if every retained input alternative and every feasible
returning path permits its intermediate operations. Discarding rejected paths
and keeping only successful ones would be unsound. Outcome correlations can
recover precision only if they are explicitly retained and checked, rather than
merged into unconditional completion facts.

The experiment checks 196 finite straight-line modular compositions against
inlined execution, plus the branch and erasure counterexamples above. This is a
semantic reference, not evidence that a finite inferred abstraction exists for
all these programs. The next design obligation is to propose that abstraction,
show how it approximates this reference conservatively, and account for loops,
recursion, conditional outcomes and latent cleanup without history explosion.

### Candidate completion-conditioned requirements

The experiment now contains a separate `CompletionSummary` abstraction for the
completion-only fragment. Each requirement pairs an access or completion check
with a finite set of receipts certified complete before that check. Returning
postconditions contain only the intersection of completed receipts across paths.
No loop iteration or call history is retained. Repeated discharge is rejected,
not eliminated by set deduplication. Unknown accesses remain requirements over
the entire modeled allocation.

For sequential composition, second-call requirements may assume only the first
call's unconditional completion guarantee. This loses branch correlations but
never uses a completion from one branch to authorize an access in another.
The experiment checks 3,200 input/program combinations against the explicit-path
reference, accepting 736. Every abstract acceptance must permit all concrete
paths, grant the caller no more authority than any returning path and retain any
obligation pending on any concrete return. The caller qualification matters:
abstractly retained workers overapproximate possible outstanding use; they do
not represent permission to resume a worker that has actually terminated.

This is a possible summary component, not a complete transformer representation.
It currently excludes lending inside the function, receipt transfer, storage
replacement, ownership, guards and newly acquired storage. Receipt order is
conservatively fixed in the experiment; nested obligations can require another
verified dependency order. The successful finite checks establish neither
precision nor soundness outside these restrictions.

Mapping to the existing compiler should keep three responsibilities distinct:

| Existing component | Required evolution |
| --- | --- |
| `SafetySummary.input_accesses/global_accesses/unknown_access` | Keep the complete may-access footprint for conformance checking; never remove accesses merely because a prior completion authorizes them |
| `completed_executions` and outcome effects | Keep returning guarantees; do not apply them early to caller state |
| `validateSummaryExecutionAccess` | Eventually discharge per-access requirements against a temporary authority view, using only certified preceding transitions; commit actual returning effects separately |
| Summary substitution and fixed point | Substitute receipt and region observations together; joins intersect prior guarantees and union requirements; unsupported cases retain entry-authority requirements |
| Virtual contracts and native imports | Erased callers use only published transition guarantees; an implementation's internal ordering cannot silently strengthen an interface |

A named input path alone is insufficient if its receipt can be replaced during
the call. Conditions must refer to the evaluated receipt observation, preserving
its exact execution identities and generations. Similarly, completing a receipt
cannot authorize later access if the accessed reference was retargeted to other
storage. Resolve those observation rules before implementing the table above.
Otherwise this would recreate the capture-time versus final-value mistake in a
new summary field.

The immediate implementation priority remains unknown-call authorization and
native physical provenance. Completion-conditioned requirements are a later
precision improvement, after their conservation and substitution rules are
specified. This model experiment changes neither compiler acceptance nor native
runtime contracts.


### Protected-access contrast

The independent experiment also tests scoped protected authority, separately
from the exhaustive loan exploration. Protection requires available write
authority; outstanding readers prevent encapsulation. A certified acquisition
places a grant in its logical execution and creates a unique acquisition
observation. Ordinary routes remain denied even in that execution: protected
access must derive from the acquisition. Several derived aliases can use the
same grant sequentially. Release revokes that observation without changing the
payload generation. Reacquisition creates a different observation, so an old
route cannot regain permission merely because the same bytes are locked again.

Explicit traces reject another execution's guard, overlapping acquisitions,
uncertified synchronization/publication, duplicate release, old guards after
reacquisition, unprotected acquisition and replacement while authority is held
by the protocol. Disjoint protected byte sets can be acquired independently.
This models certified exclusion and publication as assumptions, not as a mutex
implementation. There is no native lock or memory-order proof in this experiment.

This contrast chooses the conservative guard-derived-route policy previously
left open. The required separation is between storage observation and access
acquisition, not an exclusive reference type. The compiler implementation still
needs to express this relationship using reusable validity/authority obligations,
transport it through moves and opaque storage, and audit a native protocol. Do
not introduce a Mutex-specific rule merely because the finite example works.
General cleanup responsibility and guard thread affinity remain unmodeled here.

The semantic proposal and remaining work are in
[resource_authority.md](../plan/resource_authority.md).

### Substitution checks

The summary experiment substitutes formal receipt indices with evaluated loan
identities and formal regions with selected physical alternatives. Counterexamples
check a receipt for different bytes, a region with an additional possible target,
and two distinct formal inputs aliasing the same receipt. Substitution must still
reject duplicate discharge; distinct formal parameters do not prove independence.
A snapshot test distinguishes an evaluated receipt observation from its mutable
source slot. Retargeting within the function remains unsupported rather than
being reconstructed from final input values. These are explicit adversarial
cases, not included in the exhaustive state/transition counts above.

### Ownership and latent cleanup contrast

A separate explicit experiment adds unique cleanup responsibility and a permanent
handoff of payload authority. The two bytes now serve as a payload and an external
cleanup provider. Establishment is an audited-acquisition assumption, not a right
that ordinary code gains by holding a mutable reference. Cleanup retires payload
bytes; stale routes cannot access them. This fragment does not reallocate retired
storage or model nested resource-owning values.

A handoff moves the payload grant and responsible holder together. The recipient
must separately satisfy ordinary-access requirements of external cleanup. The
same-shaped payload is accepted with local cleanup and rejected when its cleanup
writes an unavailable provider. Lending that provider exclusively to the recipient
permits cleanup; completing the provider loan later restores access to its bytes
without reviving the retired payload. Shared readonly payload access does not
invoke cleanup, but prevents destruction or exclusive handoff while pending.
Duplicate responsibility, cleanup by the former holder and repeated cleanup are
rejected.

These are explicit traces, not additions to the exhaustive loan-state counts.
They model operation footprints as known external regions, not inferred or erased
Argi destructors. Thread affinity, synchronized/delegated cleanup, partial failure,
recursive owners, opaque storage, and recovery after worker failure remain open.
The experiment does not demonstrate transfer of String in the compiler.

### Combined transition exploration and counterexample

The experiment also combines loans, completion, protection, acquisitions, owner
establishment, handoff and cleanup. Default depth three reaches 1,254 states
through 1,687 accepted steps. Depth five reaches 13,144 states through 21,819
accepted steps, with two loans, two acquisitions and two owner records as bounds.
These counts are separate from the original loan-only exploration.

Adding an invariant for live latent cleanup dependencies exposed an accepted
sequence: destroy the provider, then establish an owner whose future cleanup
requires that provider. The establishment transition had validated payload
ownership but not the retained cleanup dependency. It now checks dependency
liveness at retention. Provider cleanup separately rejects invalidation while
another active owner retains that dependency. Both cases have explicit regression
traces. Authority at the later cleanup call remains a separate requirement; live
dependencies alone do not authorize access. This counterexample concerns the
experimental model, not a newly demonstrated compiler bug.
