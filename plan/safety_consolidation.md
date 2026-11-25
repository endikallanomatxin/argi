# Safety consolidation

Baseline: develop at `fe902869e`. The reference-content integration in the
working tree is a separate candidate. The published unknown-call gate already
checks interference against pending loans before applying completion. The
remaining storage problems can occur entirely in sequential code.

## Evaluation and evidence at ownership boundaries

An ownership-transfer probe at `581e10e4f` uses an owner whose destructor
calls an erased verifier. A call replaces the verifier in the first argument
of a two-argument consumer. When the replacement installs a concurrent
verifier, the compiler rejects the transfer. Swapping the providers makes it
accept an owner whose current verifier is local. Both programs have the same
types and call structure. The second program is a safety regression because
admission uses evidence about the overwritten slot.

The summary evaluator currently splits value inference, local replacements and
capability consumption among different expression walks. The discarded-call
walk recognizes a unary wrapper shape. The capability walk models order and
branching, but its value queries can still evaluate syntax against a later
store. A call should have one evaluation event. Evaluate arguments in source
order and preserve each by-value result and address as evaluated. Observe
call-entry referent contents through those captured addresses after evaluating
the arguments. Instantiate the result and all post-values from that entry
state before committing the post-state. A later evaluation of the same
binding uses the current store.

Apply these rules in both the symbolic and concrete domains:

- Projection of a snapshot reads its represented field. A sparse update
  inherits absent fields from its base. In a complete snapshot, an
  unrepresented field contributes no additional evidence. A stored reference
  supplies an address and lifetime dependency. Dereferencing it observes
  memory through the store at that point.
- Composition collects jointly held facts about one value or state, such
  as the dependencies of two fields of a record. An alternative-state join
  retains every possible dependency, and retains a positive guarantee only
  when it holds in every reachable alternative. Distinguish a missing fact
  from an unreachable predecessor.
- Replacement kills facts about the previous contents of the affected
  projection. Borrow roots, storage identity and destruction obligations
  change only according to their own transitions. Possible writes join the
  replacement with the surviving entry alternatives.
- Substitution interprets a symbolic value in a captured argument environment.
  The environment is local to one call and carries no historical expression
  chain. Preserve sparse updates through substitution when they still have a
  common base.

An owned worker result should use the same symbolic result relation as an
ordinary call. Its transfer obligation is evaluated against the submitted
snapshot and the result relation. The execution receipt authenticates the
result and completion so extraction can reissue ownership with fresh
generations. The result relation must account for replaced fields and each
reachable normal return. An unknown relation cannot justify retaining
caller-side metadata. Exact moves are the empty-update case of this model.

Use paired replacement tests in both directions, including nested calls,
discarded results, and conditional evaluation. Include a case where a later
argument mutates a slot whose old value was captured by an earlier argument.
Compare the same owner transformed by an ordinary call and by a worker.
Measure full-suite results and compare frontend time, peak memory, output
size and specialization counts with the same fixtures and build settings.

## Exclusive lending of a work queue

An exclusive loan of a nonplain String already works through an erased
interface and certified completion in fixture `433_owned_task_string`.
The same shape with a `RingBuffer#(UInt8)` filled with two items and a
worker removing the first item fails at the interface boundary. The
following contract covers the receiver's structural storage:

```argi
Work#(.R: Type): Contract = (
    .take: (.queue: R) -> (.item: UInt8) where { writes(queue) isolated() }
)
implement Work#($&RingBuffer#(UInt8)) (
    .take = (.queue: $&RingBuffer#(UInt8)) -> (.item: UInt8) {
        item = unwrap_or_abort(pop(.self = queue))
    }
)
```

With a local queue and an ordinary mutable receiver, constructing
`Virtual#(Work)($&queue)` reports that `take` exceeds its declared bounds.
The ordinary queue operations compile in the same program. Removing an
element accesses queue-controlled backing in addition to its structural
fields. This probe separates the interface's ability to name that backing
from the execution's ability to lend the queue exclusively.

The next contrast is to publish the backing region from the queue's owner
module and exercise the same loan without synchronization. A positive probe
should read the second item after completion. A negative probe should
reject access to the same backing before completion, including access
through an independently obtained view.

## Acceptance criterion for storage summaries

A summary describes a relation between entry and exit stores. For every
concrete entry represented at a call site, instantiating the summary must
include every exit the body could produce with those actual arguments.
Check this separately on each published return outcome. This criterion also
applies when several formal paths resolve to one cell.

Consider a helper that writes a replacement through either its first or its
second argument on every normal return. With different actual cells each can
retain its old contents. With the same stable actual cell its old contents
are gone on every return. Recording two optional writes is sound for both
calls, but cannot establish the repair in the second call. Recording two
definite writes is unsound for the first. A sufficient summary for this
example is one unconditional whole-cell replacement with a choice of
destinations. Substitute the evaluated arguments into the choice before
testing whether every alternative covers the observed cell. An uncovered
alternative prevents that proof. If payloads differ by branch, retain their
association with the destination or widen to all possible payloads.

Use this as a differential test for the body visitor and summary consumer.
Compare an inline branch, one helper and a forwarding helper, with equal,
distinct and uncertain actual destinations. Check both the repaired read and
a read that could still observe the old dependency. Re-evaluating a selector
at the next call supplies a new choice unless stability is proved. Loops can
forget the correlation while retaining every potential dependency. This test
justifies preserving a bounded destination choice where a repair needs it.
It does not require retaining arbitrary branch predicates or call histories.

A definite replacement discharges facts specifically about the previous
contents of the covered slot. Ownership disposal still requires its cleanup
transition, and reclaim still requires publication for the exact execution.
Replacing a slot that carries a receipt cannot certify completion.

### Conditional repair at a call boundary

Compile-only probe on the local integration compiler, 22 November 2026.
Start with two slots holding a live reference. Store a temporary reference in
the first slot and let the temporary expire. The repair helper is:

```argi
repair := (.a: $&Slot, .b: $&Slot, .replacement: &Int32, .choose: Bool) -> () {
    if choose { a&.reference = replacement } else { b&.reference = replacement }
}
```

Read the first slot's referent after the following operations, with a live
replacement and a Boolean parameter in the enclosing function:

| Operation | Required | Observed |
| --- | --- | --- |
| Both inline branches assign the replacement to the first slot | Accept | Accept |
| Call `repair` with the first slot twice | Accept | Reject at the read |
| Forward both arguments unchanged to `repair` from another helper, passing the first slot twice | Accept | Reject at the read |
| Call `repair` with distinct slots | Reject | Reject at the read |

The distinct-slot result checks the branch that leaves the expired reference
in place. The same-slot results isolate loss of a repair proof across a call.
All three diagnostics report an ended root. Any implementation that removes
that diagnostic for the same-slot call must retain it for distinct slots.

## Diagnosis

| Mechanism | What it represents | Where coherence can fail |
| --- | --- | --- |
| Place, symbolic pointee, captured route | Different descriptions of storage | Two descriptions may denote one cell. Distinct symbolic names prove no separation. Typed overlap must include union alternatives. |
| Validity root and generation | Lifetime dependency and incarnation | A generation can end while a reference remains stored. A shared lifetime says nothing about physical overlap. |
| Place and symbolic value tables, observed writes | Baseline content and reaching updates | A raw table lookup can bypass a write recorded under another spelling. |
| Opaque storage | Bounds on what a container retains | A bound on retained lifetimes may be sufficient for a validity check and insufficient to locate a mutation. |
| InputPath, InputRoute, ValueEffect | Caller-relative recipes | A route that locates a cell at the point of observation may resolve differently at call entry. A dependency may survive when its write destination cannot be expressed. |
| Execution state and receipts | Outstanding loans and authenticated transitions | Clearing one receipt must leave incompatible outstanding loans in force. |
| Ownership and cleanup | Responsibility plus requirements of eventual destruction | Moving an owner cannot turn a borrowed cleanup provider into owned or globally accessible storage. |

The split between lexical and symbolic representation is useful. The split
between a baseline content read and an alias-aware content read is accidental
at a semantic use site. In the candidate, `reconstructPlaceValue` refreshes
structural descendants while `readReferenceCell` overlays reaching writes.
`loadSummaryPlaceValue` and `readEvaluatedAccess` mediate some reads. Other
consumers look up values while resolving paths or captures. Each consumer must
say whether it observes current contents, an already evaluated snapshot, or
only an address. Bulk substitution of one lookup for another would conflate
these and can undo tested behavior.

The three historical counterexamples concern temporal safety inherited from
0.4: a write reaches an uncovered alternative, an effect stops at a function
boundary, and two evaluations are mistaken for the same observed reference.
0.5 adds a second consequence of stale content: a stale referent can authorize
the wrong region during a loan. Race prevention and memory publication are
additional obligations, with their own native assumptions.

## Concrete state and transitions

Model a cell by physical allocation and extent, with a separate incarnation
and initialization state. A reference value carries an access path and
observed lifetime dependencies. The concrete store can retain an old
reference after its incarnation ends. Dereferencing it requires a live
incarnation, initialized representation, physical containment, and authority.
Copying its bits neither reads the referent nor grants authority. Escaping a
borrow and invoking cleanup remain subject to their own obligations.

Track responsibility once per owned resource. Its cleanup is an operation
with a footprint, execution requirements, and dependencies. Model ordinary
authority as grants in custody of an execution or protocol, restricted by
outstanding loans. A read loan leaves compatible readers, a write loan
suspends incompatible access. Reclaim removes exactly the loan whose
completion is certified. Submission failure may restore custody only if
there was no admission that could permit access. Otherwise cleanup must
establish completion and publication. Owner transfer changes responsibility
and the required grants permanently. It does not reclaim the owner at join.

Protection deposits authority in protocol custody. An acquisition lets one
execution use that authority through an acquisition-scoped observation.
Release ends that observation and returns custody, subject to any derived
loans. Reacquisition cannot validate refs from an earlier acquisition.
A preexisting alias cannot use protected storage outside a valid acquisition.
Native synchronization must establish publication on handoff. These are
semantic transitions to validate before choosing additional checker data.

## Abstract storage interface

Use one meaning of load, store, and forget across typed Places, symbolic
cells, and opaque domains.

- Load a value from all possible current cells and include all reaching
  writes. Where contents are hidden, return only a conservative interface
  bound. An evaluated snapshot retains the facts of its evaluation.
- Store strongly only with a definite write to the same stable observation
  and enough coverage to replace the relevant extent. Store weakly to every
  represented candidate otherwise. With incomplete coverage, retain the
  unresolved effect as well. Repair of one candidate cannot erase it.
- Forget precise identity by widening destinations and weakening overwrite
  proofs. Retain retained lifetimes, cleanup, and execution obligations.
  Never use an unknown destination as an empty footprint.
- A repeated producer may create a fresh observation. Widen former
  incarnations into weak summaries at iteration boundaries. A copy of an
  evaluated reference can retain its observation while the underlying
  storage generation is live. The finite domain tracks bounded current
  observations and widened effects, with no unbounded event history.

The abstraction obligation is successor inclusion: for every concrete state
represented at entry, every concrete successor must be represented after the
abstract transition. Two candidate lists with different completeness can
carry the same dependencies. The failed experiment filtering generic source
paths caused lost FFI and execution obligations, so completeness must be
consumed by an explicit destination query independently of dependency
substitution.

## Function boundary

Publish entry requirements, may-access footprint, and a conservative
normal-return transform with separate error outcomes where relevant. The
footprint includes accesses authorized internally. A body proves those
accesses using authority established at the point of operation. A caller
supplies only the required external authority. An implementation of an
abstract contract accepts its public preconditions, stays within its
footprint, and establishes its public postconditions.

For temporal effects, retain only the state transitions needed by an interface.
For a completion followed by an access, the relevant fact is that every
conflicting access is dominated by authenticated completion of the matching
receipt. For a guarded write, the evidence is that accesses occur during
the corresponding acquisition and release closes it. A flat may-effect
summary suffices for current entry-authorized calls. It cannot express
these facts, so keep the conservative rejection until a verified transform
can publish them. Avoid replaying arbitrary traces.

A regional result binds an abstract role to an evaluated instance. To use
an entry-relative route after an intermediate write, prove stability of
the reads that locate that route. A helper may return multiple covered
routes. Substitute each route independently and retain unresolved effects
where substitution cannot establish coverage. For erased heterogeneous
storage, first use guarantees common to all alternatives. If those do not
suffice, a stronger checked interface or a later explicit dynamic proof
can recover precision. No per-call virtual capability lookup is required.

## Tradeoffs and acceptance gates

| Simplification | Complexity removed | Precision cost and control |
| --- | --- | --- |
| Alias-coherent load/store/forget | Parallel interpretations of current contents | Weak updates can retain expired alternatives. Cases 232 and 233 require preserving proven disjointness and same-observation replacement. |
| Interface bounds across erasure | Reconstructing concrete providers and element histories | A heterogeneous lookup cannot always identify one provider. Case 121 needs a shared guarantee and proved independence, while 143 checks recovery through the matching receipt. |
| Derived authority from custody and loans | Mutable bookkeeping of equivalent available permissions | Custody and derived-loan ancestry still need identity. Overapproximated overlap can reject disjoint partitions. Case 177 requires a real backing bound. |
| Compact state transforms | Full effect traces and repeated callee analysis | Some finish-and-write helpers remain conservative. Preserve order only where it changes the safety proof. |
| Widen old observations | Unbounded identities per call and loop | A repair of a newly evaluated pointer cannot kill an old write. Cases 234 and 237 require repair through a stable observation before use or reevaluation. |

For a String, prove access to its bytes separately from the latent virtual
deallocation operation. A live provider with exclusive handoff, synchronized
release, or certified delegated cleanup can justify different transitions
under the same rules. An executor outside core needs a documented audited
protocol for ingress, single admission, rollback before admission, and
completion with publication. A mutex needs the same custody rules plus
acquisition-scoped exclusion. Core privacy controls who can invoke trusted
operations. It is not evidence that their physical or publication contracts
hold.

## Migration and falsification

1. Make reads of reference-bearing cells go through one content query. Start
   with summary substitution, using the observed store as a reaching-write
   domain. Keep address-only and snapshot consumers explicit. Check aliases,
   weak writes, aggregate leaves, and expired-but-unused references.
2. Publish residual writes and complete destination evidence through the same
   caller-relative interface. Cases 229/231 with stronger regional contracts
   test capture stability and helper forwarding. Case 288 is an entry-capture
   control. Case 289X must still reject a provider that can target global
   storage. If a public contract admits an unbounded target, the compiler
   must keep the residual rather than inspect the erased provider.
3. Use the same typed load for known array candidate contents and view spans
   after a verified range proof. Case 115 checks ergonomics. Cases 285X,
   301X, 305X and 306X test escaping dependencies and raw offsets. Backing
   identity is too weak for typed element coverage, particularly across rows.
4. Only after those boundaries compose, validate move-and-cleanup and
   acquire-and-release as state transforms. Exercise partial launch, wrong
   and duplicate completion, multiple readers, stale guards after
   reacquisition, derived loans, and cleanup with an incompatible provider.
5. Remove per-consumer content overlays only after their behavior is supplied
   by the common query. Remove duplicate permission bookkeeping only after
   custody and pending obligations reproduce every authorization decision.

The bounded Zig observed-store oracle checks that joined branches and later
updates cover concrete outcomes under alias valuations. The Python resource
model independently exercises loans, owner cleanup, and protection. Neither
proves the compiler's abstraction. The missing bridge is a refinement
argument for each production load/store and summary substitution, backed by
paired compiler fixtures. If that argument requires treating syntactically
repeated calls as one reference or inventing a library-specific permission,
the representation must change before the feature is extended.

## Baseline comparison

The isolated `fe902869e` ReleaseSafe runner passed all seven named
concurrency acceptance fixtures (121, 143, 177, 232, 233, 234, 237).
The integrated compiler also built and ran all seven. Compile-only copies
of the incomplete target, caller read, and repeated observation
reductions all built on the published baseline. The integrated compiler
rejected the first and third for an ended dependency and the caller-read
case for a borrow escaping into caller storage. No reduction executable
was run. The integrated observed-store selection passed 12 unit tests.
The resource model passed its bounded exploration, including 4,951 states
and 7,472 accepted combined steps at depth four.

### Summary content query migration

The integrated checker now routes ordinary result contents and opaque
dependency collection through the same input-place loader. Its coordinate
convention starts at the immediate referent, unlike a general path over an
evaluated argument. Both concrete and symbolic storage reconstruct their
structural contents before applying the typed reaching-write query also
used by ordinary reads. Address and snapshot consumers remain separate.

The concrete and opaque increment passed 155 ReleaseSafe program checks,
including the seven acceptance fixtures and 240X through 242X. Internal
regressions check that an aggregate load retains both the prior reference
and a possibly written reference, and that a symbolic slot contributes its
stored dependency to an opaque summary without contributing the slot's own
backing lifetime. The symbolic aggregate migration also passed the focused
79-test internal summary run. It requires a separate program validation.

The symbolic aggregate change passed the same 155 program checks. The
next run included implicit referent loading, captured-region execution
retention, and all concurrency and opaque checks plus the stale FFI
capability cases. It passed 441 checks with no skips. Only 229 and 231
failed, with their existing unresolved-destination diagnostics. This
establishes the tested load migration independently of the remaining
destination-publication problem. It does not test collection case 115.

### What distinguishes the two repair fixtures

Compile-only controls for 229 and 231 isolate destination lifetime from
the repair of the original slot. Keeping the whole helper unchanged and
moving only its replacement referent to static storage allows both builds.
Keeping the lexical replacement and changing the getter to return a global
slot rejects both builds. This second implementation satisfies the same
published lifetime contract as the original getter (see also 258X).
Repairing the original slot cannot undo a store to a different slot.

A modular caller with only that contract has to account for both
implementations. Accepting the original lexical replacements therefore
requires some additional verified restriction on the destination, or
evidence retained at construction that the caller can instantiate across
the helper. A better local strong update alone cannot distinguish these
programs. The existing fixture expectations remain acceptance targets for
that additional precision.

### Acquired destinations and local reference escape

Execution fixture 255 supplies a useful control independent of view sorting.
Starting with its typed two-element allocation, writing the borrowed record
only to the indexed first slot is already rejected. Removing that store
allows compilation. Writing only to the offset second slot fails with the
same escape diagnostic. Moving both borrowed integers to global storage
allows the original two writes to compile. These are compile-only controls.

This separates two proof obligations. At slot establishment the runtime
checks the address range and, for an explicit index, the expected address.
The checker should be able to associate that destination with the allocation
whose contents retain the stored dependencies. A write must constrain any
later move, return or transfer of the owner. A local binding for the owner
is insufficient if it subsequently escapes. For a borrowed backing, those
obligations must instead follow the actual destination storage. The anchor
supplies a lifetime bound and cannot identify either destination.

Only the second store additionally needs proof that a typed offset stays
inside the original extent. A raw offset into an adjacent allocation cannot
inherit the first slot's destination. Collection case 115 needs the same
range check but starts from a lexical array with an already known identity.
Test the first-slot case independently before adding offset precision.
