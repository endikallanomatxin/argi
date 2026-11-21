# Safety consolidation

Baseline: develop at `fe902869e`. The reference-content integration in the
working tree is a separate candidate. The published unknown-call gate already
checks interference against pending loans before applying completion. The
remaining storage problems can occur entirely in sequential code.

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
