# Resource authority: proposed semantic core

Working proposal, not a closed formal system or a claim of compiler soundness.
The target is safe sequential memory/resource management and ordinary-memory
race freedom under audited native assumptions. Mutable aliases remain permitted
within one execution. References identify routes; authority controls when an
execution may use them; ownership is unique cleanup responsibility, not another
access mode. Deadlock freedom, termination and correctness of arbitrary atomic
algorithms are outside this guarantee.

This is the semantic reference for [the development gates](0.5.md).
The next bounded design checkpoint is
[safety across abstraction boundaries](resource_abstraction.md): five invariants,
permitted information loss, interface requirements and counterexample contrasts.
It is the compact review surface before further implementation; the investigations
below supply detail rather than another independent safety model.
[Concurrency research](concurrency.md), [virtual execution investigations](virtual_execution_safety.md)
and [contract projections](contract_members.md) use the same model. They must not
introduce independent permission systems. The compiler still has known
unknown-call authorization and native-buffer provenance gaps. Existing checked
loans and delegated projections do not close those gaps.

Captured-observation validity is now checked independently of the search for
concurrent access targets. Known intermediate-reference changes remain rejected
even without a pending execution. When no storage loans remain, the authority
phase no longer requires an exact captured target merely to prove separation;
the after-completion heterogeneous collection case can use its interface.
This does not prove physical independence while loans are active or complete
uniform authorization of unknown calls. See the abstraction checkpoint for the
positive/negative contrasts and the production Zig tests.

## Architecture review: lending and certified reclaim

The next implementation should test a smaller authority core before extending
the general Resource Machine. This is a design recommendation, not a completed
proof or a claim that the current checker can already be substantially reduced.
Keep the sequential storage/ownership model. Describe temporary interexecution
authority using `lend` and certified `reclaim`; describe physical execution using
a separate, audited protocol. Keep detailed region inference as a precision tool,
not a prerequisite for every concurrency abstraction.

### What the review baseline provided (995b54d66)

`core/memory/execution_access.rg` supplies `_ExecutionReceipt` and three registered
primitives: `_execution_lend`, `_execution_complete` and `_execution_input`.
`_execution_accept` is an ordinary Argi function updating a private runtime marker,
not a fourth checker primitive. Execution identities are logical invocation
identities, not OS thread identities.

* Lending collects reference loans, their read/write modes and storage
  observations. Pending loans restrict the caller. Authority is already largely
  derived from this ledger; adding another independently mutable permission
  ledger would duplicate the invariant.
* Completion discharges the receipt's matching execution identities. The
  primitive does not itself verify that a native join occurred. Its sound use
  currently depends on private core call discipline and the audited adapter.
* Worker input establishes symbolic input facts using a type, address and anchor.
  It does not authenticate the physical buffer's identity, bounds or connection
  to a particular accepted invocation. The native callback convention supplies
  assumptions that must remain explicit.
* Acceptance marks a receipt so its destructor aborts rather than reclaiming
  accepted work. A worker may start inside native creation before this marker
  changes. The actual handoff must therefore be justified by the native start
  protocol, not by treating the marker write as the start of concurrency.
* `carries_execution` and `completes_execution` check transport and discharge of
  logical obligations across functions and virtual contracts. They do not prove
  native exactly-once execution or memory synchronization.

Prepared request destruction can discharge a loan because no execution right
has escaped. Successful submission moves the receipt into the accepted task.
Native join or destruction joins the worker before core code completes the
receipt. Failed join must retain the obligation. Core privacy prevents ordinary
application code from directly fabricating these transitions; bundled core
modules are trusted peers, so privacy alone does not verify their protocol.

### Minimal borrowing rules and their certification boundary

For each loan keep its identity, source authority, target storage observations,
mode, custodian and return condition. Copying a reference never copies authority.
Readonly loans suspend incompatible writes; write loans suspend incompatible
reads and writes. Reclaim removes only the matching temporary restriction and
recomputes authority from all remaining obligations. It never restores moved
ownership, initialization or an ended generation, nor upgrades an originally
readonly grant to writing.

The execution protocol needs the following semantic states, whether or not they
are represented by separate types or runtime tags:

```text
Prepared -- accepted handoff --> Accepted -- quiescence + publication --> Reclaimable
    |                                                                      |
    +-- certified no execution right escaped --> Reclaimable                 |
                                                                           v
                                                                       Reclaimed
```

Lending reserves authority before work can start. An accepted execution right is
used at most once and stays linked to its receipt and buffers. Reclaim requires
either exclusive cancellation of a still-prepared right or certified quiescence
and publication for the accepted invocation. Quiescence includes delegated work
that could still use the grant. An error result is not automatically proof that
start failed: partial acceptance must be drained before reclaim. A cancellation
request, wake notification, result address or ordinary completion flag is not
sufficient evidence.

The certificate need not be a new public object. A checked transition on a private
linear owner, connected to an audited native handle and outcome, may suffice.
It must be bound to the exact invocation and cannot be synthesized by writing a
boolean or declaring a `where` clause. This is the main unresolved protocol
design task. Renaming `_execution_complete` to `reclaim` does not solve it.
Likewise, eliminating `_execution_input` is justified only when a shared storage
acquisition protocol establishes both physical access and worker authority;
an address with a live anchor is insufficient.

### What can be simplified, and what cannot

| Mechanism | Decision and cost |
| --- | --- |
| Separate authority bookkeeping | Reuse pending loans and certified protocol custody; do not add a second source of permission truth. |
| Exact histories of erased container elements | Do not require them universally. Use common verified interface guarantees or conservative access envelopes. Some safe heterogeneous selections will remain unprovable. |
| Arbitrarily precise region/effect inference | Keep existing useful inference; prefer reusable confinement bounds at concurrency boundaries. Less precision can reject otherwise independent operations. |
| General ordered resource effects | Defer. Keep call-entry authorization and existing conservative completion-before-access rejections until a bounded extension is justified. |
| Execution IDs, loan modes, generations and receipt transport | Essential. Removing them permits wrong-task reclaim, conflicting readers/writers or stale observation reuse. |
| Validity and physical storage evidence | Essential independently of lending. No concurrency simplification can turn lifetime into containment or initialization. |
| Cleanup and execution requirements | Essential for owner transfer. Access effects alone prove neither transferability nor synchronization. |
| Protocol-held authority and guard acquisition identity | Essential for protected sharing; a task completion receipt alone cannot express mutex exclusion. |

No existing implementation has yet been shown redundant enough to delete in
bulk. Several simplifications concern planned inference machinery rather than
code already required by sequential safety. Preserve those fixes and regression
tests. `Sigma = (V, A, O, K)` remains a semantic decomposition, not a requirement
for four independent runtime objects or checker databases.

Contextual isolation can certify that worker accesses stay within supplied
inputs and capabilities, excluding mutable ambient state. Contracts must preserve
that guarantee through virtual, indirect, foreign and cleanup calls. Unknown
effects remain unknown; isolation is not an excuse to ignore them. A broader
verified footprint can replace exact target inference, but lifetime dependencies
must not automatically become part of the access footprint. Reading string bytes
does not by itself require concurrent deallocation permission on its allocator.

Unknown identity and stale identity are different failures. A valid abstract
handle may support sequential operations without identifying its exact captured
target; it still needs valid hidden dependencies and a checked interface. Do not
relax missing-region errors indiscriminately: lost evidence and an invalidated
capture must not become interchangeable. Concurrent calls require compatibility
with every possible target or another verified isolation guarantee.

Structured borrowing is a useful optional simplification: a scope/group can own
completion obligations while futures observe results. This may simplify storing
observers in containers. It does not remove alias conflicts, certify native
completion or justify restoring authority when a handle is discarded. Preserve
existing checked futures returned through functions and individual early reclaim;
do not impose universal lexical scopes or universally blocking destruction.

Permanent owner transfer is not a loan: source responsibility and designated
authority move to the destination. Completion never resurrects the source owner.
Returning an owner is another transfer. Validate external cleanup requirements
and failure cleanup before relaxing current payload restrictions.

An inline executor needs a once-only invocation and synchronous completion
protocol; a threaded executor needs accepted handoff and joined publication;
an evented executor must retain obligations until its work is truly quiescent.
The checker should consume their guarantees rather than recognize their names.
Current external executors mainly forward or reject requests: private packet
fields do not yet expose a general safe run-once interface for an independent
executor. Exposing raw callbacks and byte buffers is not an adequate substitute.

A mutex additionally holds authority in protocol custody. Certified acquisition
grants guard-scoped access; release revokes that acquisition and publishes writes.
It does not end the protected value's generation or the execution itself. Earlier
aliases cannot bypass custody, and ordinary aliases within the guard remain
permitted. These rules share conservation with lending, but require an actual
exclusion protocol. Two job-specific transitions alone are not a complete mutex
model.

### Incremental validation before migration

1. Specify accepted handoff, prepared cancellation, worker entry and joined
   publication against the current adapter. Separate audited native assumptions
   from compiler-proved transitions. Keep current names and public behavior.
2. Connect certified reclaim to the exact receipt and physical input/output
   evidence. Test wrong receipt/buffer, duplicate invocation, premature completion,
   failed or partially accepted start, unsuccessful join and delegated work.
   Ordinary flags and declarations must not manufacture certificates.
3. Complete uniform call authorization without losing current safe programs.
   In particular retain the positive heterogeneous common-contract and
   after-completion collection cases (concurrency 121 and 143), alongside their
   conflicting variants. A coarser model must explain their acceptance, not
   change their expected outcomes.
4. Validate one independent inline executor alongside the threaded backend,
   using checked once-only ownership rather than another forwarding wrapper.
   Then test owner transfer with known cleanup, external dependencies and a
   virtual deallocator, and protected access through a mutex guard. If these
   require separate permission languages, reconsider the core before expansion.
5. Add scopes or precision improvements only when these examples show their
   benefit. Record expressivity and compilation costs before replacing existing
   inference. No broad checker rewrite is justified by this review alone.

Research supports the distinctions rather than proving this proposed design:
[Rust's join contract](https://doc.rust-lang.org/std/thread/struct.JoinHandle.html)
separates uniquely owned joining permission from completion/publication;
[scoped threads](https://rust-lang.github.io/rfcs/3151-scoped-threads.html)
illustrate why a scope must ensure joining rather than rely on a discardable
observer; [Swift's sending boundaries](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)
illustrate reusable isolation requirements at function boundaries. None replaces
Argi's sequential provenance, ownership or native synchronization obligations.

## Resource Machine: candidate operational core

### Native execution boundary checkpoint (in progress)

The current implementation work strengthens the existing three primitives,
without adding another authority category or ordered-effect representation.
`_execution_complete` now takes optional private join operands. For an accepted
receipt, normal return requires the operands' handle to match the accepted handle
and the native reclaim operation to perform successful synchronization. Missing
or mismatched operands and failed synchronization abort before logical discharge.
Prepared cancellation needs no join; the native start adapter must guarantee
that its failure return leaves no worker. Reclaim is idempotent for an already
completed receipt and does not take the result a second time.

The boundary rule is `Bound(k, h) AND Join(h) succeeds => Reclaimed(k)`.
`Bound` comes from moving the prepared receipt into the accepted handle owner;
it is not inferred from address equality between arbitrary values. All other
loans remain pending. The prepared alternative requires both exclusive custody
of the request and the native no-start failure guarantee. A successful native
start must be followed immediately by nonfallible acceptance: no fallible helper
may run between handoff and recording the handle in the receipt. Worker entry
may precede that recording, since lending has already reserved the authority.
For inline execution, callback return precedes successful handoff and supplies
quiescence by ordinary program order. For threaded execution, only successful
join supplies publication. Result-size mismatch does not join, consume a result
or discharge a loan. Cleanup failure may abort but cannot return authority to
continued code without successful synchronization.

The callback ABI now carries a private invocation descriptor containing one
native identity and the two acquired buffer addresses, sizes and alignments.
`_execution_input` accepts this descriptor rather than an independent address,
and validates the selected input type's layout. Output reconstruction validates
the matching result layout. References remain confined by the callback-local
anchor. The adapter supplies the descriptor directly from its live task state;
the stable handle links native reclaim to that invocation.

This is an audited boundary, not a cryptographic certificate or a compiler proof
of arbitrary C. Bundled core must not forge descriptors, retarget an accepted
receipt or invoke a callback outside its lifetime. The compiler still models
worker inputs symbolically rather than carrying a complete task-buffer acquisition
proof through its spatial model. Invocation addresses can be reused only after
the old task is destroyed; the unique owner and absence of escaped descriptors
are essential, not an assumption that addresses are globally unique.

`InlineExecutor` executes through the same adapter's synchronous path, sharing
buffer ownership, typed entry, result extraction and reclaim. Its callback has
returned before submission succeeds, but the public Executor contract retains
the loan until await/cleanup. `execute_inline` exposes the opaque, once-consumed
request operation to application-defined executors without exposing mutable
entry/layout fields. No compiler rule recognizes InlineExecutor.

The execution right is currently confined to the generated callback: its inputs
cannot contain owning task requests, its results cannot export owners, and
pending loans cannot escape through opaque storage. Any nested work must discharge
its obligations before callback return; detached descendants carrying these
loans are not certified by this protocol.
Only plain results and the existing nonowning payload subset remain supported.
Thread joins remain the accepted threaded backend's waiting policy; this does
not establish a blocking destructor requirement for future evented backends.

The checkpoint is not closed while unknown-call authorization and the positive
opaque/virtual composition gates remain unresolved. Those problems cannot be
fixed by treating unknown physical provenance as disjoint, or missing captured
region evidence as empty access. Existing positive expectations must remain.

Validation of the working tree: the full ReleaseSafe program suite reports
2,519 passes, 11 skips and two failures, the existing positive concurrency cases
121 and 143. All five new execution-boundary fixtures pass, as does the Debug
internal suite. The real native task probe passes ThreadSanitizer; deterministic
adapter failure paths pass AddressSanitizer/UBSan. Generated host LLVM IR passes
the invocation record by value to the C callback and retains the native reclaim
call inside completion. These results validate this increment, not the complete
concurrency guarantee or non-host ABI behavior.

The publication candidate excludes the unfinished acquisition/unknown-call
experiments. Its isolated full program suite passes 2,495 tests with 11 skips
and no failures. This preserves the published positive cases while leaving the
documented authorization gap open; passing this suite does not close that gap.

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

The prerequisite acquisition checkpoint separates presence from consumption in
the existing capability state and summaries. Checked normal establishment uses
an explicit static precondition; raw trusted integration retains its documented
caller obligations. The precondition must survive ordinary wrappers, alternatives
and reference fields, and cannot disappear at virtual conformance. Origin facts
remain metadata after consumption and never reauthorize establishment. This
requires no new permission category and does not yet establish the sealed-value
invariant below. In particular an erased factory promising only ownership still
lacks a public acquisition guarantee. Do not use that limitation as justification
to infer physical independence from its nominal result type.
Nor may each erased return mint an unrelated available permission solely because
its nominal type names a receipt. Copies of a numeric address can retain aliases
to one permission; replacing that identity could conceal consumption. A future
sealed-carrier guarantee must justify custody and transport of the authorization,
as well as physical bounds. Private fields or move-only representation alone do
not establish that semantic invariant.

The isolated acquisition checkpoint passes 2,516 program tests with 11 skips and
no failures, plus the focused native-bit-forgery regression. The Debug internal
suite passes 1,488 tests with one skip. It excludes the unfinished unknown-call
gate and loop-access precision experiment; no physical-separation claim follows
from these acquisition checks.

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

### Opaque contents preserve value relations separately from slot regions

The compiler's current opaque state retains lifetime dependencies and owner-root
associations, not the complete value relations stored there. Consequently,
recovering a valid reference to an element does not yet recover the associated
regions of a Virtual inside that element. The positive 143 regression exposes
this after completion, independently of the unknown physical-read gate in 121.

The next candidate is one conservative reference-value abstraction per complete
stored type and opaque domain, reusing existing structural projections and named
region facts. Insertions join possible target observations; they never inherit
the container's creation frame. A read borrows the joined value facts without
transferring element ownership or acquisition permission. Emptying, overwriting
or moving storage must preserve the existing generation/ownership rules rather
than simply retaining historical facts as if they were current.

The bounded opaque-capture experiment checks 1,944 member-region joins against
their exact alternatives. It needs no per-element history or new authority
algebra. It does not solve the implementation: unknown-input container reads
still need a caller-relative value relation in summaries, complete stored-type
keys must survive specialization, and borrowed observations must retain their
traversal/generation checks. A physical slot observation and the captured regions
of its contents remain distinct. Never reconstruct either from lifetime roots.
Keep missing contents evidence conservative; the experiment supplies its inputs
explicitly and does not establish them for arbitrary opaque storage.

For an ordinary helper, the returned value relation must remain caller-relative:
conceptually, `contents(input-domain, complete-type)` followed by the value's
structural/member projections. Substitution identifies the caller's domain; a
different input index is never evidence of independent storage. Resolving this
relation must separately authorize loading the element slot and invoking any
operation on its captures. A `no_access` method removes neither the slot read
nor its lifetime obligations.

The recipe experiment additionally distinguishes copied values from borrowed
element routes. Instantiate a copied result's observations at the call; do not
re-resolve its recipe against a later replacement of the container contents.
Borrowed routes instead retain the necessary generation/shape observations.
Creating fresh unknown symbolic regions at extraction would not solve this:
without a caller-relative source, effects and invalidation could disappear in
the next summary. Extend the existing value/projection vocabulary only when this
substitution can be represented end to end, including its missing-evidence case.

The current flat `InputPath` has physical projections followed by one terminal
domain. A symbolic route that projects through that domain cannot be flattened
by dropping it, moving it to the end, or overwriting it with another domain.
The checker now leaves such routes unrepresentable, conservatively refusing an
exact caller alias obligation. It separately preserves their input provenance
for hidden-lifetime escape checks. Unknown exact identity must not be confused
with local storage or an absent lifetime obligation. The direct regression
contrasts ordinary fields, terminal domains and both unsupported continuations.
The same restriction applies to locating-read inference: selecting another domain
from a path already ending in one produces an unknown access bound, while any
independent known reads remain. Overwriting the first selector is not a valid
approximation, even if the two domain indexes happen to be equal.

`InputRoute` now preserves the complete ordered sequence of physical selectors
and abstract domains when deriving symbolic caller routes. It shares the existing
storage-observation selector vocabulary; it is not another permission system.
Conversion to the current flat summary path is explicitly partial and must be
lossless. Unrepresentable routes remain exact in the checker but still cannot
publish a caller alias obligation. The bounded round-trip regression covers all
sequences of up to three selectors from two fields, dereference and two domains.
This is a migration foundation: opaque-content selectors, summary substitution
and cache publication of complete routes are not implemented yet.

#### Typed interpretation of routes

An exact selector sequence is not necessarily a well-typed query. Resolution
must distinguish a value, typed storage for a value, and an abstract set of
storage regions. In particular, `Region#(Provider)` identifies the participant
used to obtain the region; it does not assign Provider's record layout to the
region's contents. A mapping can group differently typed locations.

| Selection | Required interpretation | Result; separate obligations |
| --- | --- | --- |
| Input | Evaluated argument and declared type | Value facts or the argument's typed referent, following existing parameter conventions |
| Structural field/index | A checked record/array value or typed storage | Corresponding value/storage projection; no new disjointness beyond checked layout |
| Dereference | A valid reference to T | Typed storage for T; observing its value still requires initialization and read authority |
| Associated region | A value with verified contract evidence | Its instance's abstract storage set; not a value of the provider type |
| Opaque contents query | An identified opaque owner/domain and complete stored type | Conservative retained value observations; not ownership, occupancy or permission to read bytes |

A field after an abstract region is not justified merely because InputRoute can
preserve that sequence. It needs an independently checked typed storage view or
value query; otherwise resolution stays unknown/rejected. Similarly, selecting
another associated region requires a value carrying the appropriate contract,
not just an earlier region identity. Do not restore acceptance by assuming all
regions are provider-shaped.

For the collection case, the intended logical value recipe is the input owner's
Allocation projection, a typed opaque-contents query for Holder, its `code` value
projection, and Code's associated region. This queries retained value relations;
the physical slot read remains a distinct access obligation. Resolving the recipe
does not itself certify that an indexed element exists or is initialized. A
`no_access` method can omit accesses to its captures, never the preceding handle
load. Unknown-input containers still need this relation in their summaries;
seeding fresh region identities at extraction would not establish it.

This distinction rules out interpreting arbitrary exact routes by repeatedly
loading graph fields. The next implementation must carry typed contents facts
and their caller-relative query together, while existing flat routes retain
their current semantics. No new runtime evidence is implied by the route syntax.

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

### Factory guarantees: transport is not fresh authorization

The next public guarantee must distinguish three operations, rather than treat
all receipt-shaped outputs as freshly acquired storage:

| Operation | Evidence at the boundary | What the caller may retain |
|---|---|---|
| Forward an existing receipt | `transfers` from an identified input | The same authorization identity and its current state |
| Return a checked view of backing storage | A valid physical observation and containment | The backing relation and restricted bounds, without establishment authorization |
| Acquire new establishment authorization | A verified acquisition transition | An available authorization whose identity remains correlated with every exported alias |

The first row already has an implementation. The second and third are separate
remaining obligations. A factory might need both, but a physical observation
must not silently recreate a consumed establishment permission.

In particular, an `acquires(result)` postcondition would not be justified merely
by finding a `fresh_storage_capabilities` entry in the implementation summary.
Before adding such a clause, its verification must account for authorization
aliases exported in other results, retained provider fields, or input post-state.
A new caller-local identity for each result could hide their common consumption
state. Likewise, a helper that requires an input authorization and constructs a
private receipt does not prove acquisition: it transports the input identity.
Neither private fields nor a compiler-recognized constructor name repairs that
missing proof.

Use the following counterexamples as acceptance criteria for any replacement:

1. Copy an acquired address, forward its receipt through a virtual contract,
   establish storage through the address, then establish through the receipt.
2. Reverse the two establishment operations.
3. Export one acquisition through two result fields, then establish both.
4. Retain an acquisition alias in the provider while returning its receipt, then
   attempt establishment through both paths.
5. Return two genuinely independent acquisitions and establish both successfully.

The first two now have compiler regression fixtures, `types/416X` and
`types/417X`. They test consumption correlation across the existing virtual
transfer path, not physical containment or the correctness of arbitrary trusted
integration. The paired positive fixture, `types/418`, establishes two independent
acquisitions after forwarding their receipts, checking that consumption of one
does not revoke the other. Cases 3 and 4 remain requirements for a future factory
guarantee, not claims that a new guarantee has been implemented.

For now, retain whole-receipt `transfers` for transport. Do not introduce a
fresh-authorization postcondition as a shortcut to the physical observation
needed by collection access. The immediate design target remains the second
row: a valid bounded storage observation that can survive erasure without
claiming disjointness, initialization, ownership or a new establishment right.

### Bounded implementation experiment: references and later lexical storage

A safe reference observed at a call return denotes already existing backing.
It therefore cannot denote the physical slot of a later fresh lexical binding
in the same execution. This statement concerns physical allocation order, not
validity-root creation, value initialization, ownership or acquisition IDs.
It says nothing about separation from older storage, globals, symbolic input
referents, or storage reached by dereferencing a later local pointer.

The checker experiment records a caller-relative lexical frame on returned safe
references. Its shared proof namespace records the first declaration of each
lexical storage family. Repeated loop declarations never move that first
observation forward. Branches share the namespace, so a declaration visited on
another branch can only weaken the bound. Taking an address before visiting its
declaration records possibly preexisting storage; it cannot prove a fresh birth.
Changing a value generation never changes this physical observation.

The authorization rule is deliberately narrow:

```text
valid_reference(p) and frame(p) = F
and loan(k) targets a concrete lexical slot L
and first_declaration(L) is after F
and L was not already observed as possibly preexisting
and L contains no dereference projection
    => this reference access cannot conflict with loan(k)
```

All other pending loans retain the existing overlap checks. In particular,
unknown calls do not become bounded merely because their result is a reference.
Their effects must be authorized before the result is observed. Lifetime and
initialization checks still run; a frame cannot revive a stale reference.

Copying a reference preserves its frame. Joining known frames takes the later
bound; joining with unknown evidence forgets the bound. Missing projected fields
and dereferenced contents never inherit the physical frame of their containing
slot. A value inserted later into an older container therefore cannot acquire
that container's older separation evidence. Reference retargeting replaces its
facts rather than preserving an earlier observation.

This is an optional approximation, not an exact identity for every runtime
allocation. It is local to one proof namespace and is not exported as a raw
numeric timestamp in function summaries. A returned reference with no retained
observation receives the current caller bound, which can lose precision.
Preserving stronger bounds through abstract forwarding needs a verified source
relation; a lifetime dependency alone is insufficient.

The experiment checks a reference obtained through `Virtual` before an unrelated
local writer starts, including reads inside a loop. Paired negative programs lend
the reference's older possible backing or retarget it to the new local first.
Actual checker/state unit tests exercise joins, projections, namespace copies,
repeated declarations, early address observations and generation changes.

This does not close the heterogeneous collection case. An Allocation still
carries a raw data address rather than a published physical observation. Creating
a slot reference after the loan starts gives a weaker frame; deriving it from an
older observation will require preserving the same backing relation through
checked containment. Do not inherit a bound from an allocator lifetime anchor.

Validation resource policy for this experiment: after reported memory pressure,
stop the parallel full-suite attempt. Run focused program cases with `-j1` and
`-Dtest-jobs=1`, a 6 GiB per-process address-space limit, explicit progress and
`/usr/bin/time -v` peak-RSS reporting. The three targeted Debug internal tests
pass. The isolated ReleaseSafe program run passes all four `erased_reference`
fixtures (156--159), with 2,813,124 KiB maximum RSS and no swaps reported by
`time`, under the 6 GiB address-space limit. This includes compilation of both
the test runner and compiler, in series. The isolated full Debug internal suite
also passes: 1,491 passed, one skipped, maximum RSS 577,496 KiB and no swaps.
The isolated full ReleaseSafe program suite subsequently passes: 2,524 passed,
11 skipped, zero failures and zero reported leaks. Its maximum RSS is
2,425,772 KiB, with no swaps, under the same serial execution and 6 GiB
address-space limit. These checks validate this bounded approximation; they do
not establish general physical provenance or close unknown-call authorization.

### Next composition gate: retain observations through derived references

A focused probe reuses the existing `ArrayView` representation rather than adding
another descriptor. It takes `view(&array)` before starting an unrelated lexical
writer, then accesses the view while the loan is pending. With the unfinished
unknown-call gate enabled, the current checker still rejects this safe pattern.
Two reductions distinguish the missing evidence:

- A `code_at(&view, index)` wrapper is rejected for unknown call effects.
- Inlining the wrapper lets `get_reference` return, but reading the returned
  holder's handle slot is rejected for an unknown reference footprint.

The probe uses source matching the installed compiler's older `to_virtual`
spelling. A concurrent repository migration to `Virtual#(C)(provider)` is separate;
a stale binary's syntax error is not evidence about authority. The probe is
exploratory and does not claim validation of the migrated compiler.

This shows that adding a reference field to Allocation is not sufficient by
itself. The existing view already retains a reference at runtime. Its older
observation must also survive checked reference derivation and summary
substitution. Assigning the current frame after `get_reference` returns is safe
but loses the separation needed here. A dependency on the view's lifetime or
slot does not supply that missing backing relation.

The next implementation must therefore distinguish a verified source relation
from a may-dependency. Compare these restricted alternatives before changing ABI:

1. Preserve an existing reference observation through a verified derivation
   relation in summaries, using current input paths/routes and reference-copy
   primitives. Track coverage across every return alternative; unknown paths
   must not inherit a known branch's older frame.
2. Publish a bounded storage descriptor with an explicit semantic invariant.
   This still needs the same derivation relation when creating references to
   its contents, plus construction, zero-extent and cleanup rules.
3. Infer exact backing alternatives through all collection operations. This
   requires more historical precision than the interface should need and does
   not eliminate the need for a verified relation at erased boundaries.

Investigate the first alternative first: it reuses reference evidence and tests
composition before adding a descriptor. It must preserve prior observations,
not infer physical independence from `owns`, `depends_on`, a nominal type or a
new certificate ID. Reuse the existing lexical forwarding verifier where it
actually proves identity, but do not pretend that forwarding a reference,
selecting an offset in its backing, and loading a reference from its contents
are the same operation.

Required counterexamples are an unknown return alternative, a retargeted view,
a reference loaded from later-inserted contents, backing invalidation, an offset
outside the authorized range and a mutable alias of the backing itself. Check
both a direct accessor and an ordinary wrapper. Preserve the original
heterogeneous DynamicArray positive case; an explicitly precomputed view is a
composition test, not a replacement requirement or a permanent workaround.

A smaller regression is now registered as
`concurrency/160_reference_forwarding_preserves_separation`: obtain an erased
reference before an unrelated lexical allocation, start its writer, forward the
old reference through `forward(value) { result = value }`, then read the returned
reference. The reduced probe fails at the final read, while the corresponding
case without forwarding is covered by fixture 156. This isolates preservation
of reference identity without offsets, opaque contents or collection protocols.

Prefer a verified whole-reference forwarding relation for this first fix, rather
than treating every non-validity dependency as a guaranteed source. The existing
lexical forwarding proofs already separate exact identity from may-dependencies.
Any published relation must be checked once for the implementation and transported
in the same summary/contract representation used at calls; do not re-evaluate a
callee or add a special case for this helper's name. Losing a relation may reduce
precision, but combining an unknown return with a known return must never restore
it. Keep the bounded-subrange problem separate until the direct case composes.

#### Whole-reference forwarding checkpoint plan

Goal: preserve an existing observation across a verified whole-reference return,
without deriving any authority from may-dependencies. This implements the direct
forwarding gate above, not subrange inference or general physical provenance.

- [ ] Confirm fixture 160 fails at the returned reference's read on the current
  compiler, with a serial, memory-limited run.
- [ ] Add an optional caller-relative forwarding relation to `ValueEffect` in
  `safety_facts.zig`. It is evidence of identical returned reference values,
  not a permission and not an additional lifetime root.
- [ ] Infer the relation only after `lexical_forwarding.proves` verifies the
  complete body. Publish declared `refers_to` through the same representation
  in `contract_outputs.zig`, after ordinary conformance checking.
- [ ] Include the relation in summary equality, snapshots and cache format.
  Projection, substitution and alternative joins must discard unsupported
  relations instead of treating missing evidence as an identity element.
- [ ] At output instantiation, copy the referenced input's observation after
  normal effect composition. Preserve its old bound; never substitute a lifetime
  anchor or observe it again as fresh backing. All ordinary access, validity and
  cleanup checks still apply.
- [ ] Test direct and generic forwarding, declared virtual forwarding, an unknown
  return alternative, the wrong input, retargeting and ended generations. Keep
  fixture 156 and the ArrayView probe as composition checks.
- [ ] Validate in series under the 6 GiB process limit. Publish one meaningful
  checkpoint only after its positive and negative coverage passes. Any remaining
  rejection of derived views stays documented as an open requirement.

The forwarding checkpoint exposed an authorization bug in summary instantiation:
combining an unknown reference target with a known independent target could
select the known one and hide the unknown alias. The inverse of fixture 161
compiled while its actual selected reference pointed at a worker's borrowed
storage. The new `concurrency/164X` is build-only and records that counterexample;
it must never be executed as a runtime test while acceptance is under investigation.

A direct Zig unit reproduced the loss in both source orders. Instantiation now
includes unknown alternatives when selecting a singleton referent, handles
multiple `input_places` without last-source selection, and clears an accumulated
exact target when coverage no longer supports it. Three focused internal tests
pass, covering the union, forwarding observation transport, receiver erasure and
unknown alternatives. Full program validation of this new correction remains
pending. Do not conflate the earlier passing forwarding positives with validation
of the subsequently changed union rule.

The straight-line wrapper regression is fixture 165. The lexical verifier now
accepts compiler-internal call-to-argument relations derived only from the
selected callee's verified summary, keeping ordinary safety checking of the call
unchanged. Direct and virtual calls may supply that relation; unresolved indirect
calls do not. Forwarding through multiple wrappers converges via the existing
summary fixed point rather than recursive body inspection. Owning transfers keep
their separate explicit-move proof. Fixture 166X wraps an alternative-target
function and must remain rejected; the wrapper cannot turn its callee's missing
identity guarantee into a forwarding fact.

Four focused Debug internal tests pass, including lexical proof rejection of
missing, wrong-source and cyclic call metadata. Isolated compiler/program
validation is pending; no publication claim follows from these internal tests.

The isolated ReleaseSafe compiler now builds successfully under the 6 GiB
process limit, with no swaps. Fresh frontend builds confirm the seven new program
outcomes: 160, 162, 163 and 165 compile; 161X, 164X and 166X reject with a pending
execution diagnostic. These are compile checks, not yet fixture execution or
full-suite validation. The isolated full Debug internal suite is running next;
no checkpoint has been published yet.

The isolated full Debug internal suite passes after the forwarding composition
and reference-alternative correction: 1,499 passed, one skipped, zero failures;
maximum RSS 577,872 KiB, no swaps. The isolated full ReleaseSafe program suite is
now running in series, with the compiler already built. Its outcome remains
pending, and the checkpoint is still unpublished.


#### Forwarding checkpoint validation result

The isolated implementation passes the full serial ReleaseSafe program suite:
2,532 passed, 11 skipped, zero failures, zero leaks and zero error logs. Maximum
RSS is 2,418,512 KiB, with no swaps, under the 6 GiB process limit. The full Debug
internal suite passes 1,499 tests with one skip. The seven new fixtures include
ordinary, generic, virtual and wrapper forwarding, unknown alternatives, and the
mixed-target alias that compiled before the correction. Positive fixtures run;
negative fixtures are build-only and require a pending-execution diagnostic.

This checkpoint publishes a verified whole-reference source relation, conserves
its old lexical observation at calls, and corrects singleton target selection
when unknown alternatives are present. It does not implement subrange source
relations, physical allocation descriptors, general owner transfer, protected
sharing, or the pending uniform unknown-call gate. Those remain requirements of
the overall safety consolidation, not reasons to weaken the alias correction.

#### Identity-preserving primitive checkpoint

The same-type reinterpretation reduction fails through a wrapper after fixture
160 passes. Add fixture 167 before implementation. Reuse `forwarded_reference`
for canonical core primitives only when their selected input/output reference
types are identical and the operation preserves the address. Publish this in
the ordinary primitive summary; let the existing wrapper proof consume it.
Offsets are explicitly excluded even when the programmer supplies literal zero:
the primitive's universal guarantee does not assert reference identity. Different
referent types and mutability conversions are also left out of this bounded
identity rule. They require a weaker backing relation, not a fabricated exact
reference. Test the classifier independently of any Future or collection name.

Fixture 167 now compiles with a fresh frontend and runs successfully after
publishing identical-reference guarantees in the initial primitive summaries.
The reduced offset control remains rejected for an unknown reference footprint;
it has not been mislabeled as exact forwarding. The focused registry unit passes
and distinguishes readonly/mutable same-type identity from changed referent types,
mutability changes, offsets, raw establishment and allocation-slot construction.
The ReleaseSafe compiler build peaks at 2,874,692 KiB with zero swaps under the
6 GiB process limit. Regression-suite validation is still pending; this incremental
primitive-summary change has not been committed or published.

The primitive-identity change is isolated from the pending unknown-call/loop
experiments in `/tmp/argi-reference-forward-checkpoint`. Three focused internal
regressions pass in the primary workspace (classification, alternative evidence,
and lexical forwarding); they are not mislabeled as isolated-suite validation.
The isolated compiler rebuild and fixture validation are the next gates.

The isolated primitive-identity increment now passes all nine program checks
160--168: five positives build and run, and four negatives reject with the
required pending-execution diagnostic. New negative fixture 168X confirms that
copying the reference cannot hide an alias of the worker's original backing.
Three focused Debug internal tests also pass in the isolated tree: primitive
classification, evidence alternatives, and lexical call forwarding. No full-suite
rerun is claimed for this increment; the preceding full-suite results belong to
the previous forwarding checkpoint. There is no new runtime field or permission.
