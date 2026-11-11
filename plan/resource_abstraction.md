# Safety across abstraction boundaries

Design checkpoint following fd36db6e6. This is a candidate specification to
challenge, not a soundness proof or a description of guarantees already provided
by the compiler. It narrows the next work in [0.5](0.5.md); the detailed resource
model and research remain in [resource_authority.md](resource_authority.md).
It introduces no new permission category, language syntax or runtime descriptor.

The question is which relationships an abstraction must preserve, rather than
how precisely the compiler can recover every concrete identity. Keep sequential
mutable aliasing. Between executions, require compatible authority and authentic
protocol transitions. Soundness and modular usability are both acceptance gates.

The [uniform authorization checkpoint](unknown_call_authorization.md) implements
one bounded part of these requirements, preserving the original collection/view
positives. The wider model and internally acquired authority remain proposals;
that checkpoint is not a proof of the full five-invariant system.

## Five invariants

| Invariant | Required property |
| --- | --- |
| Valid observation | Each actual access has justified physical backing, extent, type/layout, incarnation and operation-appropriate initialization. Lifetime alone establishes neither containment nor nonoverlap. |
| Compatible authority | Two potentially concurrent ordinary accesses to overlapping storage cannot include a write. Different references, symbolic names or region members do not prove independence. A protocol grants ordinary authority only while its exclusion conditions hold. Operation-specific affinity and execution restrictions still apply. |
| Conserved responsibility | On every reachable path, cleanup responsibility and pending obligations stay with a responsible carrier until checked transfer or discharge. Reference copies do not duplicate either. This does not prove termination or eventual cleanup after abort. |
| Authentic transition | Returning authority or ending an acquisition requires evidence bound to the relevant obligation and observation. Completion includes required publication; it never resurrects storage, initialization or moved ownership. |
| Conservative abstraction | Copying, wrapping, joining states or erasing representation cannot create usable authority or silently remove a requirement. Published guarantees must remain true for every represented implementation and instance. |

Storage may remain allocated after an observation becomes stale. Conversely,
storage can remain valid after guard-derived authority ends. These invariants
therefore distinguish storage incarnations, protocol acquisitions and execution
obligations. They do not require three independent permission systems.
Retained cleanup requirements must keep their necessary dependencies valid until
responsibility is discharged or transferred. Ownership alone does not grant
authority over those dependencies; execution must still satisfy their requirements.
For an owner retaining a virtual deallocator, distinguish a live provider, a
permitted destination operation and compatibility with other provider users.
Transferring the owner requires a valid cleanup strategy, not necessarily the
right to execute cleanup on any thread: exclusive provider handoff, certified
concurrent deallocation or cleanup delegated to its original context can be
different strategies. A read-only use of the payload does not invoke cleanup.
Low-level libraries written using checked Argi operations remain within the
intended guarantee. Native C/OS implementations are an explicit audited boundary:
the compiler checks clients against their contracts but cannot prove that an
external implementation actually honors them. This is not a blanket exemption
for allocators, executors or synchronization code.

## What may be forgotten

Let `Gamma(F)` be the concrete resource states consistent with abstract facts `F`.
A conservative loss of precision from `F` to `G` requires:

```text
Gamma(F) is a subset of Gamma(G)
Allowed(G, op) implies SafeStep(S, op) for every S in Gamma(G)
```

Consequently, less information cannot justify an operation that the more precise
semantic facts forbid. This is a specification for authorization, not a claim
that every compiler heuristic accepts every operation permitted by the model.
An abstract transition must also cover every concrete successor of its input
states. A locally plausible precondition is insufficient if its post-state loses
an obligation. Unreachable states require proof; missing information is not an
unreachable state or a verified empty set.

There are three useful evidence levels, not three kinds of references:

1. An exact identity permits direct overlap and incarnation checks.
2. An abstract relationship or reusable guarantee permits operations justified
   without recovering that identity.
3. Insufficient evidence requires conservative rejection of the affected
   operation, not necessarily rejection of storing or moving the value.

For example, `exists k: Pending(k) AND Carries(value, k)` may preserve the link
needed for matching completion without exposing a numeric native identity.
Forgetting that link does not permit completion of an arbitrary pending task.
Likewise, an abstract region can remain related to a valid view and its bounds
without exposing an allocation address. Two unrelated existential names do not
establish disjoint storage.

| Information | May abstraction omit it? | What must remain |
| --- | --- | --- |
| Concrete address, binding name or provider type | Often | Valid observation and the relationships required by permitted operations |
| Exact possible target | Sometimes | A sound set of alternatives, a justified abstract region, or an interface protocol sufficient for the operation |
| Originating alias history | Usually | Relevant current validity, captured observations, possible overlap and past access requirements in summaries |
| Cleanup implementation | Yes, behind an interface | Responsibility, retained resource requirements and execution restrictions of possible cleanup |
| Concrete loan/acquisition ID | Yes, behind a binder/carrier | Unique matching relationship and conditions for return/release |
| Pending obligation | Never as an authorization shortcut | Conservative custody and restrictions until verified discharge or transfer |
| Independence or physical containment proof | Only if no permitted operation needs it | No replacement assumption based on lifetime, distinct names or ownership alone |

Known-empty, unknown and invalid evidence are different states of knowledge.
A verified empty footprint allows no memory access; an unknown footprint may
include shared storage; an invalid observation cannot authorize an access.
Losing a stale capture must not turn it into a fresh, valid unknown capture.

## What an interface must say

Reuse the existing operation description:

```text
Req(op) = (Access, Execution, Obligations, Transitions)
{ P } op { Q_outcome }
```

This is a semantic specification, not proposed source syntax. It distinguishes
requirements on the caller, possible effects, and guarantees on normal outcomes.
An implementation cannot require more than the public precondition provides,
must establish its public postconditions, and must stay within its published
effect bound. Infer ordinary function summaries; verify abstract implementations;
identify audited native assumptions explicitly.

Not every existing clause is a guaranteed postcondition. `reads` and `writes`
are upper bounds; retention clauses can permit a value to be retained rather
than promise that it was; `from_storage` permits dependency provenance, not exact
element selection or physical containment. Completion promised for one outcome
does not apply to every result. Consumers must use each clause's actual meaning.

An interface is sufficient for an operation only when callers can check these
requirements using its public guarantees and their own context. Construction of
the implementation may establish private evidence once; using that evidence must
not require inspecting the hidden implementation again. Additional exact facts
can improve acceptance but cannot be necessary for the interface's documented
baseline use. This does not promise that every runtime selection is transferable.

A common `writes(state)` bound alone grants no authority over an unidentified
state. A common `no_access()` bound can remove the method body's target access,
but not the separate read that retrieves its handle from a collection. A common
protocol guarantee can justify protected access only if its implementation and
the instance's custody/validity conditions are established.

Keep an operation's logical footprint distinct from authority required at entry.
A synchronized operation may acquire authority internally. Requiring callers to
provide ordinary write authority over its protected payload would defeat the
abstraction. The current unordered, call-entry authorization is a conservative
implementation baseline, not the final specification for such an interface.
The candidate below specifies the proof obligation for such helpers. Its encoding
in summaries remains open; do not answer it by trusting annotations or introducing
a general ordered-effect engine now.

## Authority obtained inside an operation

For each ordinary access, separate its footprint from the justification of its
authority at that point. The justification can use authority supplied at entry,
including a caller-held guard, or a grant acquired locally by a certified protocol.
These are sources of existing authority, not two new permission categories.

```text
Access(u, execution, mode, region)
requires ValidObservation(region, operation)
     and AvailableAuthority(execution, mode, region, state_at_u)

AvailableAuthority may follow from:
    an external requirement satisfied at entry; or
    a matching, still-active certified acquisition before u.
```

An acquisition relates one protocol instance, protected region, storage
observation and acquisition identity. An active grant on the wrong mutex, an
earlier acquisition or an incompatible region does not justify this access.
Operation affinity and reference mutability still apply; a readonly handle does
not become an ordinary mutable reference merely because a lock exists.

The protocol owns custody of the protected authority when no acquisition holds
it. Certified acquisition establishes exclusion and the required visibility of
earlier writes. Release revokes that acquisition and publishes its writes before
custody can be granted again. This is a protocol specification backed by audited
primitives, not a property inferred from ordinary writes to a lock flag.

For an update helper, the intended public specification is:

```text
External requirements:
    usable protocol handle, live retained dependencies, compatible execution;
    established custody of this payload by this protocol.
Effects:
    possible writes to that payload; protocol operations on synchronization state.
Normal outcomes:
    payload remains protected; internally acquired grants are returned;
    no unreported result or outstanding execution retains such a grant.
Proof:
    each payload access is covered by its own live matching acquisition.
```

The caller does not supply direct write authority over the payload. It must still
have a legitimate way to use the protocol. A valid pointer alone is insufficient:
the handle's own ordinary metadata accesses and its synchronization operations
must be safe under concurrent use. Lending a write reference to the whole mutex
object is not a general solution for sharing its handle. How to expose that
shared handle through current task eligibility and contracts remains unimplemented.
Usability does not require the lock to be uncontended; waiting and progress are
separate from whether an eventual acquisition authorizes access.

Two callers may use this guarantee when the same protocol serializes conflicting
accesses and its custody invariant holds. It cannot waive an incompatible loan
that bypasses that protocol. Protecting storage must establish custody without
outstanding conflicting use; later ordinary loans must come from an authorized
acquisition. Two independent locks cannot each claim exclusive custody of the
same payload just because their types or APIs agree.

### Body proof and modular summary

Verify every body access against its current state. A successful lock branch can
produce a grant; a failed lock cannot. Access after release cannot use that grant.
Returning normally must preserve or explicitly transfer all obligations, including
cleanup on error paths. A helper that returns a guard has a different postcondition
from a helper that acquires and releases internally.

Preserve the logical access footprint for conformance and composition. A verified
internally mediated access need not become an external payload-write requirement,
but ordinary accesses and uncovered unknown effects still do. This distinction
must survive wrappers and virtual contracts. A contract implementation must prove
the public mediation guarantee, not merely its `writes` bound; the caller uses
that guarantee without inspecting the implementation body.

Do not summarize this as "region R has some synchronized access". If a body
performs one protected write and one unprotected write to R, the latter still
requires external authority. Likewise, locking only on one branch cannot certify
all writes on both branches. Coverage must be established for each possible
access before effects are merged. A loop iteration or branch that changes the
handle or releases the acquisition invalidates the corresponding justification.

This is a proof obligation, not a commitment to storing an ordered trace or an
access-site table in every SafetySummary. A finite checked certificate for a
balanced helper may suffice. Its construction, substitution and conservative
joins must be specified before changing the current call-entry fallback. Do not
publish optimistic mediation through recursion or accept an unverified native
call as a certificate. No `synchronized` flag is proposed.

### Three demonstrations and their counterexamples

| Demonstration | Necessary relationship | Counterexample that must fail |
| --- | --- | --- |
| Protect an owned payload | Protocol custody covers the same storage observation; prior aliases cannot bypass it | Protect while another execution still holds incompatible ordinary access |
| Acquire a guard and access through it | Guard, protocol, region and observation remain linked; multiple local mutable aliases share its grant | Use the same reference after guard release, even after another acquisition of the same payload |
| Acquire, update and release inside a helper | Every internal write is justified and every normal outcome returns or explicitly transfers the acquisition | One uncovered write, a failed acquisition path that still writes, or an unreported escaping reference |

Also challenge wrong-protocol substitution, acquisition from only one incoming
branch, an unknown callback accessing outside the protected region, and a borrowed
reference passed to a child execution. The latter retains an obligation: release
cannot return custody while the child still uses the grant. Completing another
execution or dropping an unrelated guard cannot satisfy it.

An encapsulated helper returning a payload reference after destroying its local
guard fails even if the payload remains allocated. Returning the guard together
with properly related references requires an explicit retained acquisition and
different lifetime guarantees; do not infer them from the payload's lifetime.
Moving a guard transports the same acquisition, never a fresh one. Whether a
previously derived reference survives that move also depends on its validity
relationships; preserving authority alone does not settle that question.

These demonstrations are specifications for the next model validation, not
working Mutex APIs. They do not settle native unlock affinity, payload destruction
or summary representation. No Mutex implementation is introduced at this stage.

### Executable checkpoint: acquired grants and derived loans

The bounded experiment in `tools/resource_authority_model.py` now combines
protected acquisitions and execution lending through the same loan ledger.
Previously those fragments could be exercised independently, but lending from
a guard was not expressible. Naively enabling it while retaining the old early
return for guard authority would leave the lender authorized during a write
loan. Releasing the guard without tracking derived use would likewise permit
another acquisition while a child still accesses the payload.

The candidate rule is: obtain the initial grant from ordinary residence or an
active acquisition, then apply the same pending-loan restrictions. A protected
loan retains its acquisition relationship. Release requires those loans to be
discharged, including nested descendants. Completing one of two readers cannot
restore writing or permit release. A loan on unrelated ordinary storage does
not retain a guard merely because its source execution also holds that guard.

The executable checks cover ten protected-region/loan-region/mode combinations,
nested lending and partial reader completion. Twenty-six access-source cases
exercise balanced internal acquisition, acquisition liveness and mixed protected/
unprotected writes; eight mixed paths refute a region-wide "some access is guarded"
certificate. Two deliberately unsafe mutations, ignoring loans in guard authority
and allowing premature release, are detected by these checks.

Combined exploration now reaches 4,951 states and 7,472 accepted steps at depth four.
The bounds remain two bytes, three executions and at most two loans/acquisitions;
native exclusion, publication and capability establishment are assumed. There is
no Mutex implementation, general protocol proof or production summary algorithm
in this experiment. Protocol custody is represented by an immutable binding from
one protocol identity to its complete protected payload observation. Acquiring a
view of part of that payload excludes the whole protocol; it cannot create an
independent lock for the remaining bytes. Independently acquired regions require
separately established, nonoverlapping custody. Five payload/view combinations
and wrong-instance contrasts check this distinction. A mutation restoring
region-only acquisition is detected. Shared-reader protocols, dynamic protocol
destruction and operation affinity are outside this fragment.

For compiler integration, `ExecutionLoan.generations` already conserves validity
dependencies through a pending loan. A certified guard may be able to reuse that
mechanism to retain its acquisition witness. This is a reuse candidate, not proof
that a live root grants authority: acquisition-to-payload/protocol binding must
be established separately. The experimental `Loan.acquisition` field does not
mandate another production ID table or permission account.

Compiler fixtures 149--153 exercise that reuse candidate with ordinary
`restrict_reference` and a generic helper, not a Mutex or a privileged guard type.
They contrast matching completion, attempted early witness destruction, completion
of another loan, a stale reference after witness reinitialization, and independent
readonly loans with different witnesses. They validate temporal retention only:
the witness does not grant payload authority, prove physical separation or certify
a synchronization protocol. Guard movement and public mediation summaries remain
separate questions.

The distinction matters for the two compiler composition gates. An interface can
retain an abstract custody-to-payload relationship without exposing the payload's
exact address. It still cannot treat arbitrary raw storage or an unidentified
Virtual capture as belonging to that custodian. A common protocol guarantee is
useful only after instance binding and observation validity are established.
Consequently these experiments do not justify weakening the unresolved physical
slot and captured-region checks in cases 121 and 143.

## Composition and transitions

* **Copy, move and ordinary calls:** copying a reference preserves its route and
  restrictions; moving an owner transports its responsibility and obligations.
  Substitute caller relations before authorization. Different symbolic argument
  leaves are not a nonaliasing proof. Required alias conditions must be inferred
  into summaries or published at interfaces; erasure cannot remove them.
* **Branches and errors:** possible effects and possible outstanding obligations
  cover all reachable alternatives. Guaranteed facts hold on every corresponding
  exit; completion on only one branch is not unconditional completion. Track one
  responsibility per concrete path, not one new owner per abstract alternative.
* **Virtual and opaque storage:** erase the representation while retaining the
  interface evidence, validity requirements and necessary instance relations.
  Unknown-index extraction checks all represented alternatives or a sufficient
  common guarantee. Bound physical slot access separately from selected-value
  operations. Do not assume a collection was complete or empty merely because
  its type or creation-time observations provide no contents facts.
* **Lend/reclaim:** reserve incompatible authority before another execution can
  access storage. Keep the matching obligation through moves and outcomes.
  Certified reclaim removes only its restriction, considering other loans and
  the original grant. A thread, executor or completion flag is not that evidence.
* **Permanent transfer:** move cleanup responsibility and the designated authority;
  retain external operation requirements. Completion does not restore the old
  owner. Returning an owner is another transfer.
* **Protect/acquire/release:** protocol custody blocks bypassing aliases.
  Acquisition grants access under one matching guard; release ends that grant
  and publishes writes without ending the payload's storage generation. Aliasing
  inside one valid acquisition remains permitted.
* **Destroy/replace:** check cleanup requirements, current observation and absence
  of incompatible outstanding use before invalidation. Sequential aliases can
  remain present but unusable afterwards. Concurrent users impose stronger
  retention obligations, even when the caller never uses its aliases again.

Retargeting a reference must update or invalidate evidence that observed its old
target. Abstracting away the intermediate slot cannot silently preserve a stale
mapping. Access summaries must retain earlier targets used during a call, not
derive all effects from its final pointer values.

## Counterexamples and acceptance contrasts

These are design obligations, not a claim that the compiler already passes them.
Each negative changes one justification of the corresponding positive.

| Contrast | Required result and reason |
| --- | --- |
| Two mutable aliases used sequentially; lend through one and write through the other | First allowed; second rejected while authority is lent, regardless of alias spelling |
| Two readonly tasks; change one loan to writing | Shared reads allowed; conflicting overlap rejected |
| Complete `k1` while `k2` also reads the same storage | Writing remains unavailable until all incompatible restrictions are discharged |
| Complete on one branch; complete on both branches | No unconditional reclaim in the first case; matching certified reclaim in the second |
| Unknown virtual effects; verified empty method footprint | Unknown cannot bypass a loan; the empty bound still requires valid, authorized handle retrieval |
| No-access virtual method in an unrelated collection; lend the collection's actual slot | First needs proven physical independence, not target inference; second cannot bypass the slot read |
| Retrieve a captured region after joining; use a capture whose intermediate reference changed | Joining can restore authority, but cannot validate stale region evidence |
| Insert a reference after constructing a collection; invalidate its referent | Extraction must retain the insertion-time dependency; creation-time origins are insufficient |
| Read borrowed string bytes; transfer the string owner | Reading does not execute deallocation; transfer must satisfy retained cleanup requirements |
| Move owner to another execution; complete that execution | The source remains moved; no owner is recreated by reclaim |
| Release guard `a`, acquire guard `b`, then use a reference derived from `a` | Rejected even with the same payload address and storage generation |
| Two named regions or C union fields; certified disjoint buffer views | Names alone do not prove independence; verified nonoverlap can authorize parallel writes |
| Two independent symbolic inputs; instantiate both with the same caller reference | Required alias conflicts survive substitution and wrapper calls |

Working-tree cases 121 and 143 isolate different questions: authorization of the
collection slot read, and requirements on a selected value's captured regions
after completion. The latter now passes by separating known capture validation
from concurrent authorization: without pending loans, no exact target is needed
to prove absence of interference. Known changed traversals remain invalid;
sequential validity and opaque lifetime requirements remain checked. New cases
154X and 155X reject retargeting and ending a provider, and the existing nested
retargeting negatives remain rejected. That increment did not prove physical
independence for case 121 while a loan is active. The later
[uniform authorization checkpoint](unknown_call_authorization.md) supplies
authenticated backing observations for this bounded case and preserves 121/177.
It does not establish general erased extent publication. Missing evidence is
never assigned an empty footprint; [reference mutation composition](conditional_reference_mutation.md)
also has to preserve possible destinations before any loan starts.

## Correspondence with the existing checker

| Existing mechanism | Role and remaining decision |
| --- | --- |
| Places, symbolic pointees, roots and acquisition facts | Observations and overlap approximations; lifetime and different symbolic names must not imply physical separation |
| ValueFacts, DomainFacts and ValueEffect | Value/instance relationships; distinguish unknown from invalidated capture and define conservative joins |
| SafetySummary access bounds and unknown effects | Call requirements and effect bounds; authorize every call form before applying unordered postconditions |
| Execution loans, receipt paths and outcome completion | Conserved custody and exact discharge; reuse the audited native join/entry boundary |
| Opaque dependencies and ownership transfers | Retention and cleanup; do not reinterpret `from_storage` as a typed contents or physical-location guarantee |
| InputPath and InputRoute | Different representable route subsets; keep checked conversions, not an immediate uniform representation rewrite |

Remaining decisions are concrete: which abstract relation survives typed opaque
extraction, how invalidation differs from absence of precision, and what a public
protocol contract needs to encapsulate protected access. No new facts should be
added without substitution, join, invalidation, transport and authorization rules.

## Exit criteria for this design checkpoint

Implementation validation now prioritizes Zig tests over enlarging the Python
reference experiment. `checker.zig` directly exercises retained witness roots
through caller-relative completion summaries, nested receipt carriers and branch
joins. The two matrices cover 16 loan/witness/completion combinations and 16 pairs
of branch completion outcomes using the production checker/state operations.
They check exact discharge, preservation of other pending obligations and absence
of witness resurrection. Fixtures 149--153 separately test those relationships
through the language frontend and generic wrappers. These are temporal retention
checks, not a Mutex implementation or a closure of the opaque authorization gate.
Keep the Python experiment as bounded design history; do not build a parallel
production checker or treat its passing results as implementation evidence.

The earlier isolated publication candidate passed 2,503 program tests (11 skipped)
and 1,480 Debug internal tests (one skipped), with no failures.
Unfinished acquisition and unknown-call authorization experiments were excluded
from that candidate; they are not a description of current implementation status.
The later authorization and mutation checkpoints are linked above. The green
suite establishes that increment's regression baseline, not completion of the
remaining concurrency guarantees.

For each contrast above, write down the retained relationship, the public
requirement and the rule allowing or rejecting it. Then identify which existing
facts suffice and which case still lacks a representation. Preserve the same
results through an ordinary wrapper, a generic wrapper and an abstract interface
when their published guarantees are unchanged. A client justified by a public
contract must not need the hidden implementation body.

Count necessary client annotations and record conservative rejections alongside
soundness results. Library authors may need explicit contracts; ordinary clients
should use ownership, references and acquisition APIs. Do not declare success
merely because negatives reject or because exact identities happen to be visible
in all positive examples. The finite Python experiments are supporting searches,
not a proof of these abstraction rules. This checkpoint proposes no compiler
refactor or new unsafe extension.
