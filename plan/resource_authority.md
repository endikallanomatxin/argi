# Resource authority: proposed semantic core

Design specification for the concurrency safety work, not a claim about current
compiler guarantees. This is the common model for the
[0.5 development gate](0.5.md). [Concurrency research](concurrency.md) and
[virtual execution safety](virtual_execution_safety.md) provide examples and
implementation investigations; they do not add independent permission systems.

## Guarantee and limits

The target is freedom from ordinary-memory data races in safe code, assuming
audited native primitives satisfy their contracts. It does not imply deadlock
freedom, logical atomicity, cancellation progress or correctness of arbitrary
atomic algorithms. The current compiler does not yet establish this guarantee:
unknown call authorization and native buffer provenance remain known gaps.

Sequential mutable aliasing remains valid. The user should normally need
ownership, references and protected access; abstract regions and operation bounds
belong mainly at library boundaries. Rejection is preferable to inventing evidence.

## State and identities

The semantic state contains four kinds of facts:

| Fact | Meaning |
| --- | --- |
| Resource `(s, g)` | Storage identity `s`, observed generation `g`, initialization and validity dependencies |
| Authority `A(e, r)` | What logical execution domain `e` may do to access region `r` |
| Responsibility `O(v, h)` | Holder `h` must eventually transfer or clean up owner `v` |
| Obligation `L(k, e, r, g, m)` | Pending protocol instance `k` retains mode `m` over a specific observation |

Ownership is a unique responsibility, not a third memory access mode. An owner
may remain responsible for destruction while temporarily lacking write authority.
A holder can be an execution or an owning container carrying its obligations.
Execution domains are logical identities; neither a physical thread nor an
executor's nominal type identifies one.

An access region is storage selected by checked provenance, an abstract contract
mapping or a certified storage operation. It is not the transitive closure of
lifetime dependencies. Distinct identities alone do not prove disjointness.
Overlap follows known layout and alias facts; unresolved alternatives may overlap.
Separate allocations can share an allocator dependency without sharing payload
authority. A new generation never makes an old observation valid again.

## Operation requirements

Use one description for a function, selected cleanup, virtual method or certified
protocol step:

```text
Req(op) = (Access, Execution, Obligations, Transitions)
```

- `Access` bounds every ordinary read/write that may occur, including global,
  indirect and hidden accesses. Unknown is an unbounded requirement, not empty.
- `Execution` states destination, affinity and synchronization prerequisites.
- `Obligations` states retained dependencies, authority and cleanup responsibility,
  including requirements of operations that remain permitted on a stored value.
- `Transitions` states verified postconditions: moves, invalidation, retention,
  completion, publication and responsibility discharge, potentially by outcome.

A destructor's requirements remain latent in its owner. Reading a payload does
not execute that destructor. Sharing a readonly string therefore need not require
concurrent deallocation, but its owner must remain unable to destroy the borrowed
bytes. Moving the string does not authorize its destructor on another thread.

`reads` and `writes` currently describe ordinary memory access. A synchronized
logical update is not an ordinary write exempted by a flag: its implementation
must obtain the required authority through a certified protocol. Affinity and
publication cannot be inferred from the existence of an access bound.

## Authorization and conservation rules

1. **Access.** Every observation must be initialized and live, and the execution
   must satisfy the operation's access and execution requirements. For potentially
   concurrent `e` and `f`, overlapping regions permit shared reading, but
   `W(e, r)` excludes ordinary `R(f, r)` and `W(f, r)`. Aliases inside `e` use the
   same authority. Destroying or replacing borrowed storage requires compatible
   authority over every affected observation.
2. **Lend.** A read loan freezes incompatible writes; an exclusive loan suspends
   incompatible reads and writes in the lender. Its exact protocol identity,
   region, generation, mode and validity dependencies remain pending. Ending a
   root or replacing a generation cannot bypass that obligation.
3. **Move and retain.** Ordinary moves transfer responsibility and its attached
   facts; they do not authorize cross-domain use. Owning storage must preserve all
   hidden obligations on every path, including failure and cleanup. Erasure,
   forwarding and extraction cannot strengthen authority or drop requirements.
4. **Transfer.** A handoff must distribute authority without incompatible outside
   access and establish that every operation permitted in the destination has
   usable resources. Cleanup can remain elsewhere only under an explicit retained
   responsibility. A type's shape alone establishes neither condition.
5. **Complete.** Restoration requires evidence for that exact outstanding protocol
   instance, actual completion and memory publication. It discharges only matching
   obligations; another worker's loan stays pending. It never recreates a consumed
   owner, renews an old alias or revives an invalid generation.
6. **Synchronize.** A protected region is inaccessible to ordinary aliases outside
   its protocol. Successful acquisition supplies scoped authority; release revokes
   derived access before publishing writes and returning authority. Runtime
   exclusion and publication must be provided by audited primitives. Serialization
   needs an explicit protocol guarantee, not merely a shared executor.

Linearity prevents duplication of responsibilities; matching storage, generation
and protocol identities prevents discharging the wrong responsibility. Both are
necessary. Forgetting or discarding an observer is not evidence of completion.

## Composition and erasure

Calls substitute actual storage identities into the same requirement description.
Composing effects must distinguish a copied argument's local slots from referents
reached through its reference fields. Virtual methods publish requirements over
abstract regions; each instance binds those regions without revealing its type.
Implementations must satisfy the published bound, including cleanup and callbacks.

Conservative may-access effects require authority at call entry; postconditions
apply afterward. This deliberately rejects some helpers that complete a loan and
then access its storage. Splitting completion and use into separate calls remains
valid. A general ordered-effect graph is outside this design gate.

Moves, joins and opaque extraction preserve guarantees common to all possible
values and requirements from every possible value. Correlated alternatives may
be retained when already represented; otherwise the result is conservative.
Do not reconstruct missing facts from the implementation selected at runtime.

For heterogeneous strings with unknown deallocators, either preserve sufficient
contextual evidence, store values certified against a common contract, or reject
the operation. Dynamic conformance acquisition is a possible later extension.
`Virtual` remains two pointers; no descriptor or implicit runtime check is proposed.

## Contract relations and instance bindings

A contract quantifies over abstract resource roles. A value occurrence has a
semantic binding `B(value, contract, role)` to an access-region expression and its
observation evidence. This binding is analysis state, not a proposed runtime map.
Equal role names or local numeric domain indices in different occurrences do not
identify the same storage. A binding may conservatively describe alternatives;
missing identity is unknown, never an empty region.

The implementation must prove its access, execution and obligation requirements
fit the public preconditions, and every published postcondition holds on all
applicable returning paths. Erased callers use that public description together
with instance bindings, without consulting the concrete implementation summary.

Keep the following relations independent:

| Relation | Establishes | Does not establish |
| --- | --- | --- |
| Validity dependency | An observation needs a root to remain live | Target identity, containment or authority |
| Reference target | Which storage an existing reference designates | Ownership or cross-domain permission |
| Region binding | Which resources an abstract role denotes | Compatibility of accesses or synchronization |
| Acquisition | Unique establishment evidence for physical storage | Initialization of an arbitrary value |
| Protocol identity | Which retained obligation a transition matches | Actual completion or publication by itself |

Returned values need post-relations when their consumers require them. For
example, a factory forwarding a counter may establish:

```text
B(result, Counter, state) = B(source, Counter, state)
```

This is semantic notation, not new Argi syntax. `depends_on(result, source)` alone
cannot establish this equality: another live counter could have a different
state. A returned reference into an opaque buffer has the same problem even
without Virtual. Projections or partitions need their own checked containment
relation; equality must not be guessed from shared lifetime dependencies.

Calls substitute these relations through the same summaries as ordinary outputs.
Moves and handle copies preserve their occurrence relationships. If a captured
reference is retargeted, its old mapping must be updated by a proven transition
or cease to authorize calls through that capture. Relations distinguish entry
from proven post-call observations; a final binding value alone does not prove
when a capture was taken. Storage and generation evidence must stay correlated.

Whole-value forwarding already has a useful stronger relation: the existing
`transfers(result, source)` contract preserves the complete moved value, including
its instance bindings. This does not transfer cross-domain authority. Likewise,
`refers_to` preserves an existing reference's target. Prefer those established
relations when they suffice; a new region clause is justified only for a case they
cannot describe, such as constructing a new capability with selected result-role
bindings. The generic transfer tests cover nested virtuals, compatible reads and
incompatible writes; lifetime-only publication and a different transferred input
remain rejected. Heterogeneous extraction likewise preserves common verified
contract guarantees without recovering arbitrary per-element region identities.

Concrete factories may infer such relations. Existing `ValueEffect.domain_values`,
`input_domains`, `input_places` and `DomainFacts` are starting points, not proof
that public contracts already express every required relation. The current
contract-output builder's lifetime facts must not be reinterpreted as result
region bindings. An erased factory must publish a sufficient relation; knowledge
of a convenient selected implementation is not a substitute. A collection transports its guaranteed relations and obligations,
not arbitrary per-element precision. Dynamic extraction needs a common verified
guarantee, retained alternatives sufficient for authorization, or rejection.

Consequently, a wrapper's own representation and its captured provider are
separate regions. `writes(self)` cannot authorize the delegate's resources.
A closed forwarding contract must state the relevant binding or requirement;
blanket recursive access to all lifetime dependencies is not an alternative.

## Native evidence boundary

A native primitive's contract must identify its resources, preconditions,
transitions, synchronization and failure/cleanup behavior. FFI permission does
not itself prove containment, transfer or synchronization. A lifetime anchor does
not prove that an arbitrary address belongs to an owned access region.

An acquisition receipt can certify physical storage without certifying initialized
values. A borrow needs region membership and a responsible owner without acquiring
that ownership. These statements must remain distinct when resolving native task
buffers. No new trusted operation should be introduced without an audited source
of evidence and an explanation of why existing operations cannot express it.

## Minimal implementation gate

The following must use the same rules, including through generic helpers and
virtual contracts:

| Case | Required evidence |
| --- | --- |
| Shared readonly references | Compatible reader authority; owner cannot invalidate their observations |
| Owner with a known local destructor | Unique responsibility and destination authority, with cleanup exactly once |
| Owner retaining an external reference | The above plus preserved dependency and access obligations |
| Owner retaining a virtual deallocator | The selected cleanup's abstract requirements survive erasure |
| Factory returning a virtual capability | Published result-to-input or fresh-resource bindings suffice for its consumers |
| Mutex and guard | Isolated protected storage, acquired scoped authority, revoked derived references and publication |
| Unknown or heterogeneous requirement | Explicit verified refinement or conservative rejection |

These cases have the same authority flow:

- **Shared payload:** the owner lends reading of its bytes, retains cleanup
  responsibility, and cannot invalidate them. The deallocator is kept live but
  is not invoked. Completing one reader does not discharge another reader's loan.
- **Transferred owner:** the handoff moves responsibility and payload authority;
  the selected destructor still requires authority over its actual provider.
  That provider must be exclusively handed off, usable through a certified shared
  protocol, or covered by a retained cleanup delegation. A lifetime edge alone
  selects none of these alternatives.
- **Protected payload:** construction confines the value's authority to protected
  storage; acquisition lends it to a guard's execution. Interior mutable aliases
  share that authority. Release ends guard-derived access and publishes writes
  before the protocol can grant another execution access.

Before broadening payload eligibility, cover each applicable transfer's success,
failure, discard, alias and lifetime cases. Before claiming the full guarantee,
close unknown virtual/indirect/native access authorization. Reject missing evidence
without adding a library-specific exception. General channels, advanced
cancellation, pools and green threads are later work, not simultaneous 0.5 gates.

Existing representations provide the implementation starting point:

| Requirement | Existing representation | Still missing |
| --- | --- | --- |
| Access | `SafetySummary.input_accesses`, `global_accesses`, `unknown_access` | Complete authorization of unknown effects and native buffer provenance |
| Execution | Isolated callback checks and explicit FFI dependencies | General affinity, transfer and synchronized-operation requirements |
| Obligations | Owned roots, dependencies, opaque provenance and execution receipts | Common transport of latent operation requirements through arbitrary owners |
| Transitions | Input post-states, invalidated domains, opaque transfer effects and completion paths | General protected access and certified publication protocols |

One semantic model does not require one universal runtime token or a new record
on every reference. Extend or consolidate these existing representations only as
a concrete gate case requires. This document prescribes neither new syntax nor a
second summary system.
