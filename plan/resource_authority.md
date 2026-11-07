# Resource authority: proposed semantic core

Working proposal, not a closed formal system or a claim of compiler soundness.
The target is safe sequential memory/resource management and ordinary-memory
race freedom under audited native assumptions. Mutable aliases remain permitted
within one execution. References identify routes; authority controls when an
execution may use them; ownership is unique cleanup responsibility, not another
access mode. Deadlock freedom, termination and correctness of arbitrary atomic
algorithms are outside this guarantee.

This is the semantic reference for [the development gates](0.5.md).
[Concurrency research](concurrency.md), [virtual execution investigations](virtual_execution_safety.md)
and [contract projections](contract_members.md) use the same model. They must not
introduce independent permission systems. The compiler still has known
unknown-call authorization and native-buffer provenance gaps. Existing checked
loans and delegated projections do not close those gaps.

## Resource Machine: candidate operational core

The provisional name Region-Based Execution Authority describes the intended
semantics, not a new user-visible feature or a separate checker. Write the logical
state as `Sigma = (V, A, O, K)`: validity, authority, cleanup responsibility and
pending obligations. Physical memory, current execution and possible concurrency
are parameters of the machine, not facts inferred from permission names.

Storage has an allocation identity `a` and an extent `[lo, hi)`. An observation
also carries an incarnation `g`, initialization and provenance. Keep physical
overlap separate from observation validity: two accesses to overlapping bytes
conflict even if their recorded generations differ. A stale generation makes an
access invalid; it never proves disjointness. Zero-sized values may still carry
logical ownership/cleanup obligations although their byte intervals are empty.
C unions, interior views and dynamically indexed storage need explicit overlap
rules; unresolved overlap is possible overlap.

A Region member denotes a set of storage observations. Distinct members are not
fundamentally disjoint. The current implementation's rejection of overlapping
named domains is a conservative restriction supporting independent invalidation,
not a theorem derived from their names. Do not relax it until alias-aware
invalidation and every consumer of domain independence are accounted for.
Lifetime dependency edges do not add the dependency's bytes to this set.

A reference supplies a checked route and type-level mutability, not an independent
authority token. Reading requires valid provenance, live backing storage, an
initialized selected value and compatible read authority. Writing additionally
requires reference mutability, write authority and the existing initialization
or replacement/cleanup protocol. Invalidating storage requires compatible
invalidation authority even if its destructor has no ordinary writes.

Represent authority abstractly as conserved grants over overlapping storage:
exclusive ordinary access, shared reading, or authority held by a protection
protocol. Several aliases in one execution use the same grant. Copying a handle
cannot split or create grants. Permissions must remain compatible across all
potentially overlapping executions, including runtime workers currently paused.
An executor identity proves neither serialization nor physical thread affinity.

Candidate transitions, independent of library names:

| Transition | Preconditions | Conserved result |
| --- | --- | --- |
| Copy reference | Valid route and permitted value read | Same target observation; no new authority or responsibility |
| Lend read | Authority may be split for reading; no incompatible writer | Exact loan record; incompatible writes suspended; compatible readers retained |
| Lend write | Exclusive transferable access authority | Destination grant; lender's incompatible access suspended |
| Move owner locally | Available owner and valid move | One new holder of the same responsibility and attached obligations |
| Transfer owner | Local move plus destination operation/cleanup compatibility and valid authority distribution | Responsibility and designated grants move together; external dependencies remain explicit |
| Complete | Matching live protocol instance, actual quiescence and required publication | Discharge only that instance; recompute authority from remaining grants and loans |
| Destroy/replace | Unique applicable cleanup responsibility, live operands, no outstanding use, authorized cleanup footprint | Consume responsibility and invalidate only selected observations; preserve external obligations |
| Protect | Available authority, checked encapsulation and compatible existing loans | Authority held by protocol; old aliases cannot bypass it |
| Acquire/release | Certified protocol step and matching acquisition identity | Scoped grant, then revocation of derived access and publication before reuse |

A loan records its source authority and restoration policy. Completing one reader
must not manufacture write authority if the original grant was readonly, another
reader remains, authority was transferred, or the storage has ended. Repeated,
wrong-instance and stale-generation completion cannot duplicate grants. An
observation of completion is not by itself permission to reclaim storage.

Protected authority needs an acquisition identity distinct from storage generation.
Release ends guard-derived permission without destroying the protected value.
Whether preexisting aliases can be used by the acquiring execution is an open
policy: the smallest initial rule should require access through guard-derived
routes. Cross-thread unlock and task migration must respect operation affinity.
Atomic access to protocol state grants no access to unrelated ordinary memory.

## Functions as resource transformers

A candidate specification is `{P} f {Q_outcome}` with a may-access footprint `M`.
It describes safe returning executions and preservation through all intermediate
steps, not termination or eventual cleanup. Divergence, abort and native failure
must have explicit boundaries; an affine permission system alone cannot prove
that every allocated resource is eventually released.

For a contract implementation, require `P_public => P_impl`,
`Q_impl => Q_public`, and `M_impl <= M_public`, after substituting instance-region
bindings. Include latent cleanup and execution requirements. A public contract
must not erase an inferred alias precondition it cannot express. The frame rule
requires compatible, untouched framed resources and stable invariants; it cannot
frame arbitrary aliasing state around an unknown footprint.

`reads`/`writes` bound possible access; they neither grant authority nor prove
synchronization. Unknown is top, never an empty set. Every call form and selected
cleanup must discharge the same requirements. While loans are pending, an unknown
footprint needs a verified confinement bound or conservative rejection. Ordinary
sequential acceptance does not establish concurrent authorization.

A pre/post pair plus unordered may-access effects does not by itself distinguish
`complete(k); write(r)` from `write(r); complete(k)`. A future bounded transformer
must retain enough evidence to establish that every path reaching the access has
completed the matching obligation. The relation between `k` and `r` must be
substitutable at callers. Completing another task, a conditional unsuccessful
join, or merely requesting cancellation is insufficient.

Investigate a finite domain of authority-changing transitions and access
requirements conditioned on certified earlier transitions. Do not commit to its
representation yet. Join control-flow conservatively; recursive summaries need a
finite abstraction/widening with monotonic convergence. Successful straight-line
examples are insufficient if branching, failure or recursion loses obligations.
Keep the existing entry-authority check as fallback whenever such evidence is
missing. This is a research gate, not permission to apply all completion
postconditions before a call's accesses.

## Native storage and publication evidence

Keep four independent claims: an address, acquired physical extent/alignment,
initialized typed contents, and authorized access. A fifth claim, quiescence with
publication, is needed before restoring a worker's borrowed authority. Neither
`ffi`, a `no_access` declaration nor a live anchor creates these claims.

The native task buffer is a witness case for a general acquired-storage protocol,
not justification for a TaskBuffer compiler primitive. Compare Argi-owned stable
buffers borrowed by the adapter with native-owned buffers returning authenticated
acquisition/containment receipts. Specify establishment, initialization,
publication, failure and release in either design. Receipts must bind the actual
allocation and observation; integers or asserted where clauses cannot forge them.
The worker's callback validity and exactly-once output initialization are separate
proof obligations from join's publication guarantee.

### Choosing a buffer protocol

The native adapter allocates input/output buffers and exposes an integer
result address after join. An unmerged integration experiment copies plain
result bytes through initialized by-value native blocks into aligned local
storage, without converting that native address to a caller-side safe reference.
`trusted_establish_inherited_reference` supplies a lifetime dependency, not a Place
or authenticated access region. Existing
`allocation_slot` likewise supplies lifetime facts without complete concurrent
physical-region authority. Reusing either alone cannot close unknown-call
authorization safely.

| Candidate | Required evidence and cost |
| --- | --- |
| Argi owns stable acquired buffers; native worker borrows them | Retained physical extent/region identity after acquisition permission is consumed; initialization/publication states; cleanup joins before release |
| Native owns buffers and returns authenticated storage observations | General native acquisition evidence tied to the real allocation and owner, not an arbitrary integer; separate initialized result and reclaim transitions |
| Join copies into caller storage | Checked destination extent/alignment and initialized representation; copy footprint covers every byte; source remains native until join completes |

Copy-out may simplify result lifetime, but does not remove initialization or
physical membership obligations. Current `zeroed` intentionally does not
initialize arbitrary result records, and native writes to erased `Any` cannot
certify arbitrary typed storage. Do not expand either guarantee as a shortcut.
Prefer acquired-region evidence reusable by ordinary allocated collections;
select ownership/layout only after its transitions and failure behavior are
specified. The existing native race probe can be instrumented as described in
[testing.md](../docs/testing.md#native-task-race-instrumentation), independently
of the unresolved compiler evidence.

### Physical observations and abstraction: required distinction

The current integration exposes a useful counterexample: a collection element
contains a virtual handle whose operation has `no_access()`. Selecting the
operation still loads that handle from collection storage. The operation's
empty body footprint cannot authorize this preceding load. A closed footprint
for slot establishment is a separate issue: checking an Allocation receipt's
bounds reads the receipt, not the pointed-to bytes, and establishes no access
authority by itself.

Represent a physical observation abstractly as `(B, range, generation)`, where
`B` overapproximates possible backing identities. Authorization must hold for
**every** possible backing and the selected range. A missing backing relation
means unknown access, not an empty footprint. Distinct observation, owner or
acquisition names do not prove different physical bytes. A suballocation must
retain its backing relation; erasure may add alternatives but must never remove
a possible overlap. Observation validity and current authority remain separate.

The executable experiment checks bounded selections against authenticated
extents, overlapping receipts, stale generations, missing evidence and 48 erasure
monotonicity cases using the existing authority state. Its authenticated extents
are concrete oracle hypotheses. It does not implement a checker inference rule
or establish how an abstract interface creates a valid observation.

That last point is the remaining design obligation. Exact whole-value transfer
can preserve an existing certificate; a factory producing new storage needs a
verified output guarantee. `owns` alone publishes cleanup responsibility, and
`depends_on` alone publishes lifetime. Neither publishes physical membership.
A native acquisition origin retained only by a concrete implementation also
cannot establish an erased interface guarantee. Conversely, requiring all
allocator outputs to denote independent fresh acquisitions would incorrectly
exclude arenas and other shared backing providers.

Before adding a production effect, specify the weakest universal guarantee that
supports both newly acquired storage and checked subranges of existing backing.
Its implementation check, caller substitution and erasure must preserve possible
aliasing. An existential valid range alone does not prove disjointness from a
pending loan. An interface must preserve a usable relation, publish a stronger
verified guarantee, or conservatively reject the access. Private runtime bounds
are important to audit containment, but their mere presence in a nominal record
is not a new static proof rule. Do not special-case collection access or consult
a concrete allocator body to manufacture the missing public guarantee.

### Preferred candidate: a sealed physical-storage value

Do not add an allocator-specific `has_storage` assertion merely to make the
current regression pass. A more compositional candidate is a sealed physical
storage value, retained inside owners and views. Its semantic interpretation is:

```text
WFStorage(v) = exists backing, range, observation.
    live_physical_extent(backing, range, observation)
    and encodes_bounds(v, backing, range)
    and bounds_not_retargeted(v, observation)
```

This predicate does **not** contain write authority, initialization of arbitrary
contents, cleanup responsibility, thread transfer or establishment permission.
Native acquisition proves it at a small audited boundary. Checked subranges
preserve the backing identity and restrict the range. Copies/moves preserve its
observation; invalidating its supporting owner ends the observation. An ordinary
integer address, nominal owner or live anchor cannot construct such a value.

The motivation is semantic encapsulation: RustBelt verifies abstract library
types by giving them semantic interpretations and proving exported operations
satisfy those interpretations ([Jung et al., section 6](https://people.mpi-sws.org/~dreyer/papers/rustbelt/paper.pdf)).
This is a design analogy, not a proof of Argi. Do not import arbitrary user-defined
logical predicates or a general invariant prover into the compiler. Investigate
one restricted storage capability supplied by the resource kernel, using the
existing acquisition receipt and authenticated bounds where possible.

A well-formed value of this sealed type would preserve physical validity through
an abstract return signature even when its exact backing is existential. That
would follow from its type's verified construction discipline, **not** from
`owns`, `depends_on`, a vtable flag or inspecting a hidden implementation. This
requires auditing construction, casts, zeroing, reflection, field writes, native
returns, VM materialization and opaque extraction. Private fields alone are not
an implementation of that discipline. Existing numeric Allocation bounds have
not yet established this semantic invariant.

#### Existential backing and caller frames

An existential observation may alias an existing input, retained provider or
another existing allocation; it is not a fresh physical allocation. Nevertheless,
a physically valid observation cannot point into a *later fresh lexical
allocation*. This is an allocation/frame property, not lifetime-root separation.
A candidate abstraction bounds possible lexical backing by the caller frame at
publication, while retaining unknown external backing. Old globals and symbolic
input referents remain possible aliases. New views never gain physical freshness
from a new certificate identity.

The finite experiment contrasts an older validated storage value with a later
independent lexical loan, and rejects the corresponding old-storage loan. It
also exposes an important counterexample: using a container's construction frame
for a value inserted later can fabricate disjointness. The frame belongs to the
physical observation being transported. Writes/retention and control-flow joins
must widen possible backings when new values are introduced; storing a reference
never inherits an older container's non-aliasing guarantee. Retargeting or
replacing a certificate cannot preserve its old frame proof.

The 72 additional finite checks validate conservative erasure against explicit
byte alternatives. They do not prove the allocation/frame theorem or provide
compiler scope inference. Before relying on this abstraction, specify its link
to actual allocation identities, owner validity, summary instantiation, loops
and opaque storage. Existing acquisition IDs or validity-root creation times
must not be substituted for that evidence. If this abstraction costs more than
preserving explicit backing alternatives, keep the latter and reject unknowns.

#### Implementation gate for this candidate

1. Retain a validated physical-storage value through acquisition and establishment;
   consuming establishment permission must not destroy physical evidence.
2. Derive views through checked bounds operations, including arena children that
   share backing. Do not assume a new observation means independent bytes.
3. Make erased signatures preserve only the verified type invariant, with
   conservative backing alternatives; preserve stronger exact relations through
   existing whole-value transfer when available.
4. Authorize accesses via the resulting storage observations using the same
   authority checker as ordinary references. Metadata bounds checks remain
   distinct from the eventual content read.
5. Preserve the heterogeneous virtual collection positive case unchanged; reject
   aliased backing, expired owners, stale/corrupted bounds, receipt reuse and
   late insertion into old containers. Do not enable the gate merely because a
   type name or private record layout matches.

This is the preferred next experiment, not an implemented public type, finalized
ABI or completed soundness argument. It avoids adding an independent proof
language to every contract while testing whether one reusable storage capability
can cross the existing abstraction boundaries.

### Physical observation representation: constraints for implementation

The next compiler fact should describe a **view of backing storage**, not turn
the existing acquisition-origin list into a permission. A view needs possible
backing identities, a bounded range and the validity observation supporting its
use. Distinct views may share backing. Physical overlap is checked only after
validating both observations; authority is checked independently afterward.

The separate physical-heap experiment checks 900 view pairs and adversarial
release, reuse and reset traces. Its `PhysicalFrame` erasure checks the actual
validated backing against a set of allocation identities, excludes later fresh
backing, and retains possible aliases of existing backing. Late insertion into an
older container requires widening the inserted value's frame. Its allocation oracle supplies nonoverlapping
live backing. The conclusions to preserve in the production abstraction are:

| Operation | Required fact | Result and limitation |
| --- | --- | --- |
| Native acquisition | Audited live extent, size and alignment | A new physical backing identity; no initialized arbitrary contents |
| Checked subrange | Live parent view and validated bounds | Same possible backing, restricted extent; no physical freshness |
| Retain in an owner | Verified construction and lifetime relation | Persistent view independent of consumed establishment permission |
| Copy or move | Valid existing view | Preserve its backing and observation; do not refresh them |
| Reset owner | No incompatible outstanding use | End its observations; backing may remain live |
| Release backing | Matching responsibility, no outstanding use | End every view of those bytes; an old descriptor must not survive release |
| Reacquire a reused address | New audited acquisition | New backing identity; old observations remain invalid |
| Erase exact origin | Verified descriptor invariant and conservative alternatives | Preserve valid physical membership; do not assert disjointness from existing storage |

A publication frame therefore contains **semantic allocation identities**, not
numeric addresses, receipt IDs or validity-root creation times. A fresh view of
old backing cannot refresh that frame. A sealed descriptor's construction must
also bind its numeric extent to the same logical backing; changing an address
or size field cannot preserve the proof merely because its owner remains alive.
This is the concrete invariant to check before making it a type-level guarantee
that survives a virtual factory signature.

[Low*'s buffer model](https://fstarlang.github.io/lowstar/html/LowStar.html)
provides a useful precedent for separating reference-backed slices, liveness and
framed disjointness. It does not justify mapping Argi lifetime dependencies to
physical regions, or importing a general refinement solver. Prefer checked
constructors and the existing finite summary coordinates. The physical experiment
still assumes authorized reset/release, and it does not establish the compiler
abstraction or close the heterogeneous collection gate.

The `PhysicalLoans` bridge now checks the outstanding-use part of that assumption
against the existing byte-authority model: 576 bounded view/mode combinations
retain backing and owner-generation observations until certified completion.
Ending a different descriptor's generation never restores authority over aliased
bytes. Releasing unrelated backing is permitted; releasing borrowed backing is
not. Matching release responsibility remains an assumption of this fragment.

An empty byte selection is not an empty obligation. A pending zero-sized view
still retains its owner generation and backing even though ordinary byte-access
checks find no conflict. Keep liveness obligations independently of the physical
access footprint. Logical invalidation itself need not write bytes, but physical
reclamation or reuse must also satisfy the corresponding access requirements.
This is a conservation rule for the existing validity/authority dimensions, not
a new permission category or a special rule for tasks.

### Acquisition identity: implementation audit and candidate

`State.establishCapability` already allocates nonreused identities and
`consumeCapability` changes a separate availability state. This is a useful
starting point: consuming establishment permission need not erase acquisition
identity. Established Allocation data now retains an acquisition-origin identity separately
from the consumed establishment permission, with matching direct and summary
transfer. This is provenance metadata only: it grants no physical range,
initialization, owner liveness or access authority. `allocation_slot` still
returns lifetime dependencies without complete physical membership evidence.
Ordinary raw references therefore cannot currently participate in access
authorization as authenticated acquired storage.

A candidate reuses the acquisition origin identity while separating two facts:
linear establishment authorization and persistent membership of a checked range.
The second fact must never be fed back into capability-use counting or permit a
second establishment. Do not put a consumed capability into a field that existing
code interprets as an available authorization. No extra runtime token is implied;
whether a new static fact category is necessary depends on its consumers.

Required propagation is acquisition -> established owner -> bounded slot/view ->
borrowed reference, preserving origin plus checked range/observation and owner
validity through moves and summaries. Offset/reinterpretation must preserve or
restrict that range, never enlarge it solely from a new type's size. Unknown
ranges conservatively overlap within an acquisition. Partition independence
requires explicit evidence; separate lifetime roots alone are insufficient.
Acquisition origin also does not prove allocator-provider authority for cleanup.

Before implementation, specify how region membership is represented in InputPath
substitution and contract roles, how branch alternatives preserve possible aliasing,
and how current owner invalidation ends every derived observation. Regression
cases must cover consumed-permission reuse, inspected address aliases, independent
acquisitions, arena children sharing backing storage, out-of-bounds projections,
moves, owner replacement, opaque extraction and returned references. Missing
membership must remain unknown, never an empty footprint. This audit is not an
implemented guarantee or a justification for a task-specific primitive.

## Evaluation and unresolved design obligations

This proposal is coherent as a direction, but not yet a complete formal model.
`(V, A, O, K)` is an organization of facts, not a proof that their interaction is
sound. The difficult missing definitions are:

- A permission algebra over partial overlap, shared loans and restoration from
  restricted source grants, including partition/recombine and unions.
- How acquisition-scoped authority is tied to usable routes without changing
  permissive sequential aliasing or allowing old aliases to bypass protection.
- A finite, compositional representation of latent cleanup, execution affinity,
  result-region relations and authority-changing function summaries.
- Operational rules and a simulation from compiler facts to machine states,
  including opaque storage, joins, exceptional exits and native assumptions.

Prefer the smallest rules explaining a case over a new clause for its library.
Reuse existing summaries; a new universal runtime token or a parallel effect
system is not implied. Two-pointer Virtual remains the default representation,
not a proof that arbitrary erased instance information can always be recovered.
Exact identities, conservative alternatives and verified common interface
guarantees are different evidence levels. Missing evidence remains unknown.

A proposed preservation claim is `Safe(Sigma) and Sigma --op--> Sigma'` implies
`Safe(Sigma')`, conditioned on valid audited primitive implementations. Establish
spatial/temporal validity, compatible authority, unique cleanup responsibility,
conservation of outstanding obligations and protected-access protocol integrity.
Ordinary-memory race freedom would follow only after covering the operational
semantics and proving the static checker sound with respect to it. No such proof
currently exists. Tests or a finite model search can find counterexamples; neither
establishes that theorem for unrestricted programs. Native race instrumentation
also does not prove absence of bugs.

Before implementing more concurrency, write the small transition system and
work through adversarial traces: two readers completed separately; initially
readonly authority; wrong receipt; write before/after join; failed join;
retargeted capture; overlapping union fields; aliases predating protection;
guard escape; moved owners with external cleanup; heterogeneous extraction; and
failure cleanup while workers remain live. Use a bounded executable model to
check conservation and erasure monotonicity, then consider Lean/Rocq once the
rules stabilize. Do not start by verifying the entire compiler.

## Contracts, instance relations and erasure

Use one operation description for static calls, selected cleanup, virtual methods
and certified native steps:

```text
Req(op) = (Access, Execution, Obligations, Transitions)
```

Access bounds ordinary memory effects, including indirect and global effects.
Execution requirements include affinity and certified synchronization.
Obligations retain dependencies, grants and responsibility, including latent
cleanup requirements. Transitions describe moves, invalidation, retention,
completion and publication, potentially conditional on outcomes.

A region member is a static role whose instance binding is
`B(value, contract, role) = storage observations`. Equal member names or numeric
indices in different contracts or occurrences do not identify the same storage.
Missing identity is unknown, not an empty region. Region mappings grant neither
ownership nor access. A wrapper's representation, its delegated receiver and the
selected captured region are distinct. Locating reads and observations of
retargetable handles must survive summary substitution and erasure.

| Relation | Establishes | Does not establish |
| --- | --- | --- |
| Lifetime dependency | Required root remains live | Physical containment, target identity or authority |
| Reference target | Storage designated by an existing reference | Ownership or cross-domain permission |
| Region binding | Storage observations denoted by an abstract role | Disjointness, access permission or synchronization |
| Acquisition | Authenticated physical extent/establishment evidence | Initialized arbitrary typed contents |
| Protocol identity | Exact obligation/acquisition being matched | Completion or publication by identity alone |

Factories require result-to-input or fresh-resource relations when consumers need
them. `depends_on(result, source)` cannot establish
`B(result, C, role) = B(source, C, role)`. Existing `transfers` preserves whole-value
facts and `refers_to` preserves an existing reference target; reuse them when
sufficient rather than adding a new clause. Neither grants cross-domain access.
Final binding values cannot substitute for capture-time observations.

Calls must distinguish local copies of argument fields from referents reached
through reference fields. Moves preserve obligations; unions retain requirements
from every possible value and guarantees common to all alternatives. Heterogeneous
extraction needs exact identity, sufficiently conservative alternatives, or a
verified common interface guarantee. Otherwise reject. Dynamic evidence is a
possible explicit extension, not a descriptor added automatically to every Virtual.
The two-pointer handle remains the default, not an axiom requiring impossible
static recovery of arbitrary runtime selections.

Reading borrowed String bytes does not invoke its deallocator. Ownership transfer
must nevertheless account for that latent operation: exclusive provider handoff,
a certified shared protocol, or retained cleanup delegation. A shared allocator
lifetime does not merge independent payload regions. General owners must preserve
responsibility, dependencies and permitted operations through storage and errors.

For an exclusive owner handoff, transfer the payload grant and cleanup holder in
one checked transition. Requirements on external cleanup regions remain separate:
they can be temporarily lent, synchronized by a certified protocol or retained by
an explicit cleanup delegate. Do not return payload authority by completing an
external provider loan after that payload was destroyed. A borrowed read of the
payload does not require executing its destructor but must prevent invalidation.
The bounded experiment exercises this distinction; recursive owners and failure
cleanup still require general rules before compiler payload eligibility expands.

Retaining a latent cleanup requirement requires valid observations of its
external resources at retention time. Those retained obligations must prevent
incompatible invalidation until responsibility is discharged or verifiably
transferred. Checking authority only when cleanup executes is too late if an
intermediate transition can destroy its required provider. This rule applies to
any retained operation, not only a deallocator or task payload.

## Implementation correspondence and acceptance gates

Reuse existing representations rather than designing a second checker:

| Existing representation | Unresolved requirement |
| --- | --- |
| `SafetySummary.input_accesses`, globals, unknown effects | Uniform authorization of every call/cleanup form; unknown is never empty |
| Owned roots, dependencies and opaque provenance | General transport of latent cleanup and execution requirements |
| `InputPath`, `ValueEffect`, `DomainFacts` | Instance/result relations through substitution, joins and heterogeneous storage |
| Execution receipts and completion outcomes | Exact discharge and authenticated publication without reviving generations |
| Acquisition receipts | Physical membership distinct from lifetime, initialization and authority |

Current may-access summaries check authority at entry and apply postconditions
later. Preserve that safe fallback; do not apply completion early simply because
it appears in a postcondition. A bounded completion-conditioned summary is a
candidate precision improvement, not implemented permission to reorder effects.
For each access it could retain certified preceding receipt observations, while
keeping the full footprint for conformance checking. Joins intersect preceding
guarantees and union requirements. A replaced receipt slot or retargeted reference
must not silently change which obligation or storage those conditions denote.
General lending, ownership and acquisition transitions need separate validation
before extending this completion-only candidate.

The [executable experiment](../tools/RESOURCE_AUTHORITY_MODEL.md) is a bounded
counterexample tool. Its explicit-path reference and finite summary comparison
are not compiler code or a proof. Keep research results beside the tool; keep
remaining design obligations here. Before expanding functionality, explain these
cases with the same rules, also through generics, Virtual, storage and errors:

- Compatible readers with independent completion; no write restoration from an
  initially readonly grant, wrong receipt or outstanding nested obligation.
- Owner transfer with local cleanup, then an external dependency, then a virtual
  deallocator; cleanup and failure preserve one responsible holder.
- Protected storage with aliases predating protection; guard-derived permission
  ends on release and stays ended after reacquisition.
- Heterogeneous extraction and returned capabilities retain sufficient relations
  or reject conservatively, never infer authority from lifetime.
- Unknown ordinary/virtual/callback/native effects cannot bypass pending loans;
  valid borrowed await and forwarding executors remain supported.

Native protocols also need instrumentation and interleaving tests. ThreadSanitizer
can find races but does not prove a protocol correct. A mechanized preservation
proof and a compiler-to-model simulation remain research obligations. Scheduling,
green threads, general channels and advanced cancellation should not grow while
these foundations lack an agreed account. Release order belongs in 0.5.md.

## Research basis and limits of the analogy

These primary sources motivate parts of the proposal; none proves Argi sound:

- [Bornat et al., Permission Accounting in Separation Logic](https://flint.cs.yale.edu/cs428/doc/permission.pdf)
  develops fractional and counting approaches to read sharing. Use conservation
  and compatibility as a basis, without making each ordinary alias exclusive.
- [Iris](https://iris-project.org/) and [RustBelt](https://plv.mpi-sws.org/rustbelt/)
  demonstrate resource/invariant reasoning and semantic justification of unsafe
  library abstractions. They are proof frameworks and results for their models,
  not an inference algorithm to embed wholesale in Argi.
- [Swift SE-0414](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)
  provides a concrete precedent for contextual transfer based on connected values.
  Its isolation regions are not automatically Argi's physical access regions.
- [Pony reference capabilities](https://tutorial.ponylang.org/capabilities/reference-capabilities.html)
  illustrates local mutable aliasing with restricted sharing/transfer. Its
  reference-capability discipline should not be presented as Argi's semantics.

## Complexity boundary informed by other systems

[Mezzo's retrospective](https://drops.dagstuhl.de/storage/00lipics/lipics-vol032-snapl2015/LIPIcs.SNAPL.2015.221/LIPIcs.SNAPL.2015.221.pdf)
reports practical inference difficulties despite a regular permission model,
including heuristic search, annotation requirements and problematic diagnostics.
Its authors deliberately limited static disciplines and used dynamic ownership
checks for some difficult sharing patterns. This is a warning about inference
cost, not evidence that Argi should adopt Mezzo's mutable-alias restrictions.

[Verona's region-capability model](https://arxiv.org/pdf/2309.02983) organizes
objects into isolated region forests and localizes mutation to an active region.
Its structural confinement is stronger than Argi's ordinary reference model.
We can learn from its explicit boundaries without assuming its region-local
results apply to arbitrary Argi aliases or allocator dependencies.

[Koka's effect inference](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/koka-effects-2013.pdf)
shows a modular type-and-effect design with inferred row-polymorphic effects.
An effect row does not identify Argi's per-instance physical regions or encode
receipt-specific authority transitions. Adopt compositional inference as a goal,
not a second general algebraic-effect system to solve concurrency.

These comparisons motivate the following limits for the proposed checker:

- Infer structural routes, finite region alternatives, selected cleanup and
  monotone requirements over a bounded vocabulary. Specify widening or a
  conservative fallback before introducing a new recursive summary dimension.
- Keep interface guarantees explicit and reusable. An erased call uses those
  guarantees; it must not rediscover a convenient concrete implementation.
- Do not infer arbitrary separation-logic entailments, synthesize protocol
  invariants, or search ownership graphs for an unspecified cleanup policy.
- Prefer a common verified interface guarantee or a precise missing-evidence
  diagnostic when heterogeneous values lose their instance relations. A dynamic
  refinement can be designed later for a demonstrated use case.
- Exercise real surface programs alongside model traces: parallel readers,
  owner transfer with external cleanup, protected access and heterogeneous
  extraction. Record necessary annotations and reject new abstractions that
  require ordinary callers to manipulate proof bookkeeping everywhere.

These are design constraints, not established termination or complexity bounds.
A new semantic fact must have specified substitution, join, erasure and failure
rules before entering the implementation; a passing isolated regression does not
justify adding an independent permission mechanism.
