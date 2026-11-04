# Concurrency: access authority and execution obligations

## Status and purpose

This note records open work toward general resource transfer and execution
requirements. Development order belongs in [the release plan](0.5.md).

The native Future and ThreadedExecutor support plain results and nonowning input
records or arrays whose reference leaves point to plain data. Checked execution
receipts preserve loans through ordinary calls, wrappers and executor erasure;
completion restores matching authority. `is_plain_data` and `is_borrowable_data`
are shape queries, not general transfer guarantees. Isolated callbacks also reject
mutable globals through transitive access summaries. The precise implemented
boundary is described in [the concurrency specification](../description/173_concurrency.md).

Extend that boundary to owning resources, opaque obligation transport, virtual
access effects, affinity and synchronization before claiming general race freedom.

## Principles to preserve

- Multiple mutable aliases remain valid within one execution domain. Do not
  introduce general exclusivity for `$&T` or require explicit access tokens at
  every sequential read and write.
- Exclusivity is a temporary property of authority between potentially concurrent
  executions, rather than a permanent property of a mutable reference.
- Aim for freedom from ordinary-memory data races in safe code under verified
  trusted primitives. Do not promise this until the whole boundary is covered:
  globals, FFI, callbacks, virtual calls, destructors and synchronization.
- Separate safety from scheduling. Executor, Mutex and Channel should be library
  compositions of general mechanisms, not names recognized by the checker.
- Keep explicit capability injection. Network and FileSystem remain independent
  of Executor; no implicit global runtime is required.

## Three independent dimensions of safety

| Dimension | Question | Relevant information |
| --- | --- | --- |
| Validity | Does the storage still exist, and is this observation valid? | Places, storage generations, validity roots, initialization, ownership and provenance |
| Access authority | Which executions may read, write or destroy this storage? | Access regions, shared reading, exclusive access and outstanding loans |
| Execution requirements | Where and under which protocol may an operation run? | Affinity, external capabilities, transfer restrictions and synchronization |

Reuse existing safety summaries, opaque storage domains and dependency tracking
where possible. Access authority must nevertheless remain independent of validity:
a live resource can be unavailable to the current execution while another holds
its authority.

An execution domain is logical, not a physical thread ID. A task can migrate
between workers while retaining authority, provided its resources permit that
migration. Local or thread-affine tasks need separate execution restrictions.
Single-threaded suspension also permits reentrancy and interference with program
invariants; memory safety and data-race freedom do not imply logical atomicity.

## Regions, aliases and resource dependencies

An access region identifies storage whose ordinary accesses must be coordinated.
It is not automatically a validity root, an ownership tree or the full transitive
closure of lifetime dependencies.

For example, a String owns an allocation and retains a virtual deallocator that
may depend on a GeneralPurposeAllocator. Its payload can be isolated even though
other allocations use the same allocator. Do not merge all those payloads merely
because they depend on one provider. Instead, account separately for accesses to
the payload and operations on the provider, including latent deallocation effects.

Region analysis must follow aliases through references, aggregate fields, returned
values, opaque storage and virtual captures. A reference hidden in a Box still
reaches the same referent. When independence cannot be proved, assume possible
overlap. Precision may improve later; safety cannot depend on optimistic aliasing.

A small candidate permission rule uses `R(e, r)` for ordinary reading and
`W(e, r)` for ordinary reading and writing. For distinct, potentially concurrent
domains with overlapping storage:

```text
W(e1, r) implies neither R(e2, r) nor W(e2, r)
```

Multiple readers may coexist; mutable aliases within one domain share its
authority. Destruction, replacement and generation termination must also respect
outstanding access. Synchronized or atomic operations need their own verified
protocol, rather than being ordinary writes exempted by assertion.

The general identity and granularity of regions, treatment of unknown referents,
and joins across branches and loops need a formal definition beyond the current
plain-referent task loans. A single global
flag toggled on an object by async would not preserve obligations across calls,
aliases and hidden storage.

## Moving ownership, lending access and transferring execution

These are distinct operations:

- Moving with `~` transfers ownership and cleanup responsibility.
- Lending grants another execution temporary read or exclusive authority while
  preserving obligations to the original storage.
- Transferring across executions additionally checks that retained resources and
  all permitted operations are usable in the destination.

Conceptually:

```text
transferable(value, destination)
    = isolated(value, destination)
      and resources_usable(value, destination)
```

This cannot necessarily be a type-only Transferable conformance. Two Strings
have the same type but may retain different virtual deallocators with different
requirements. Contracts can provide reusable guarantees; contextual analysis must
check the concrete value and its retained evidence.

A pending concurrent loan is stronger than an ordinary sequential reference.
Sequential safety can permit destroying an owner and reject subsequent alias use.
A worker may already be using its alias, so a pending loan must prevent ending its
root or replacing its generation until certified completion. Retaining a valid
reference at submission time is insufficient.

## Transitive and latent execution effects

Infer ordinary function access effects transitively, including globals, callees,
callbacks and selected cleanup. A destructor is a latent operation carried by an
owner: moving only a String's bytes does not account for its eventual call into
a shared allocator.

Reference inputs and known field paths now support checked `reads`, `writes` and
`no_access` bounds, independently of lifetime and ownership clauses. Paths can name
references in by-value records and captures in statically known receivers. Named
receiver domains also bound erased captured regions, using existing implementation
mappings and preserving identities through wrappers. The implicit receiver region
is separate from the handle's own storage. Symbolic receiver evidence is retained
rather than inventing a concrete place or publishing an empty effect set.
Unknown and global effects cannot satisfy a closed bound. Intermediate-reference
mappings, general symbolic domain storage and synchronized access remain open;
ordinary memory effects do not certify unknown native behavior.

Virtual interfaces must preserve a conservative bound on permitted access effects
through type erasure, including captured provider identities. Their implementations
must be checked against that bound. Erasing a concrete type must not erase the
information required to authorize its operations or destruction.

Deallocator exposes an important unresolved choice:

- One contract with access effects that survive virtualization is general, but
  requires evidence transport through Virtual and Allocation.
- Separate concurrent interfaces make an erased guarantee easier to name, but
  risk duplication and do not fully describe an unsynchronized provider used
  exclusively on different threads at different times.

First define the general effect guarantee; introduce specialized capabilities
only where necessary. With no verified concurrent guarantee, conservatively
require exclusive access to a virtual deallocator's provider. Do not synchronize
all allocators: confinement and exclusive transfer remain useful strategies.

Execution guarantees belong to individual operations, not just a type-wide
`ThreadSafe` classification. Distinguish confined allocation, exclusive transfer,
concurrent remote deallocation and cleanup delegated to the originating domain.
A resource may permit reading in one domain while requiring destruction in another.
These are requirements to represent, not guarantees of current Allocation values.

## Acquiring additional virtual evidence

Keep implementation-wide guarantees separate from instance-specific authority,
affinity and captured resources. A possible future representation is an immutable
conformance descriptor referenced by a method table, retaining the two-pointer
handle. This is an open design, not implemented RTTI or a commitment to that layout.
Thread IDs and instance-specific affinity do not belong in a shared method table.

Ordinary calls should use the contract's static evidence. Recovering an additional
hidden guarantee may require an explicit fallible acquisition once at a transfer
boundary, followed by a refined capability or retained proof. Every witness must
be verified for all instances covered by it; captured-provider requirements may
still need instance evidence. The acquired proof must track its exact value,
generation and retained capabilities through moves and storage. Replacement or
changed captures must invalidate or re-establish it. No descriptor flag by itself
grants authority, prolongs a lifetime or discharges an execution obligation.

## Partitioning and serialized access

Prioritize isolation, ownership transfer and independent partitions alongside
shared-state synchronization. A checked split of one initialized buffer should
produce disjoint ranges without requiring general proofs about dynamic index
arithmetic. Existing aliases to the entire buffer must still conflict with loans
of either partition. Partition identity must survive views, calls and moves.

Scheduler-certified serialization is a separate possible source of isolation.
A serial executor prevents overlapping handlers but need not fix their physical
thread; a local executor may impose affinity without preventing suspension and
reentry. Merely sharing an executor proves neither property. Any serialization
guarantee needs an explicit trusted protocol and must account for reentry.

## Conserved obligations and certified transitions

The conceptual operations needed are:

| Operation | Obligation |
| --- | --- |
| Lend access | Suspend incompatible access while another execution holds a loan |
| Transfer access | Move authority to a different execution domain |
| Retain obligations | Preserve authority, dependencies and cleanup in an owner or opaque domain |
| Synchronize completion | Prove execution has ended and its effects have been published |
| Restore access | Return exactly the authority justified by completed obligations |

The current checked `carries_execution` and `completes_execution` effects
conserve task receipt obligations through virtual dispatch. Generalize obligation
transport through opaque storage and owning resources without relying on lifetime
dependencies alone.

Opaque transport needs identities finer than the domain's conservative union of
hidden dependencies. Extracting one slot must recover only that slot's execution
obligations; completing it must not release sibling tasks. Domain-empty markers
are not completion evidence. Until that protocol is represented, reject retaining
pending receipts, including nested and summarized transfers. Error-path cleanup
cannot certify completion when another path retains the receipt.

Exclusive authority cannot be duplicated, silently lost while work continues or
returned early. Evidence must identify the actual storage, relevant generation,
receiving execution domain and outstanding execution. An old receipt cannot
restore authority for a newer generation or complete a different task. Restoring
access must never revive invalid references or consumed ownership.

Summaries, wrappers, virtual dispatch and opaque storage must preserve these
relationships. Obligations need a responsible owner on every success and failure
path, not just a linear token disconnected from the resource it protects.

## Task ownership and lifecycle

A provisional TaskEnvelope would retain:

- A statically generated callable exposed through a monomorphic entry.
- Stable input and output storage with initialization and cleanup state.
- Argument ownership and result extraction responsibility.
- Lifetime dependencies, access obligations, external capabilities and affinity.

Prepare arguments in the caller: defaults and assumed inputs must not be evaluated
again by a worker. Moving a Future must not move storage referenced by execution.
Copying a representation is not a transfer of ownership or safety evidence.

An accepted task carries authorization to execute exactly once. The current
move-only TaskRequest carries a private execution receipt but is not yet a general
owning payload abstraction. Candidate lifecycle:

```text
Prepared -- submission rejected --> recover or destroy prepared inputs
    |
    +-- accepted --> Pending --> Running --> Completed
                                              |
                                              +--> take result
                                              +--> discard result with cleanup
```

Specify failure and cancellation paths too. No path may execute consuming work
twice, free running storage, publish uninitialized output or return an owning
result without its dependencies. Completion must authenticate the same task
storage and publish its final state before extraction or reclamation.

InlineExecutor, ThreadedExecutor and a future EventedExecutor should discharge the
same obligations with different policies. A small trusted native boundary must
certify start, completion and synchronization. Arbitrary C thread creation plus
a declared `where` clause cannot establish that proof. Executors built on certified
primitives should remain ordinary checked library code.

Separate responsibility for execution completion from observation of its result.
The current Future combines them and joins on destruction; that is a prototype
policy, not a universal requirement. Blocking a sole scheduler worker during
cleanup could deadlock. A different owner may retain execution until completion,
but dropping an observer must never abandon live storage obligations.

Structured task groups are a possible extension for borrowed tasks: all work
must finish before the enclosing scope releases borrowed resources. The current
Future instead retains its loan until a successful join or joining cleanup. Detached work
requires independently surviving resources and a stable completion owner.

## Synchronization and ownership transfer

Mutex should encapsulate protected storage and expose it only through a Guard.
Construction must not hide external aliases that can bypass protection. Multiple
mutable aliases derived within one guard remain valid; all must become unusable
when its authority ends. Existing lifetime tracking may support this relation,
but the construction and escape rules still need checking.

Lock and unlock must establish real memory publication through audited atomics or
OS synchronization. Static authority alone does not create happens-before.
A semaphore's multiple permits do not automatically authorize writes to one
shared region; its resource protocol must specify what each permit grants.
Keep resource budgets, access authority and completion obligations independent.

Channels naturally move ownership from producer to queue to consumer. They must
retain access and execution obligations as well as payload bytes. Failed sends,
close, cancellation and destruction of queued messages need exactly-once cleanup.
A channel must not make a nontransferable resource transferable by hiding it.

Neither Mutex nor Channel should depend on a particular executor. They can serve
executions from different schedulers and use each waiter's resumption mechanism.
Actors could then be built from channels and confined storage without becoming
the mandatory language execution model.

## Waiting, cancellation and scheduling

Keep waiting independent of backend policy. Distinguish the roles of a wait
source, an owned registration, a wake handle and the current execution's wait
context without committing to four public types.

A notification is neither successful acquisition nor proof of completion. The
protocol needs try, register, recheck, park, notify and retry semantics that handle
lost wakeups, duplicate notifications and contention. Registration ownership must
remain valid while a notifier can access it. Cancellation racing with notification
must safely remove or retire the registration.

Start with cooperative cancellation and distinguish:

```text
cancellation requested != execution completed != resources reclaimed
```

A running worker may still use its resources after a request. Ordinary exits
should perform cleanup; cancellation must not free storage prematurely. Define
which waiting and queue operations preserve progress when cancelled.

Keep native threads as the initial backend without choosing stackful green
threads or stackless transformation yet. First specify a backend-neutral wait
interface. Green threads would additionally require suspended-stack lifetimes,
cleanup, context switching, migration constraints and adapters for blocking FFI.
Do not promise transparent suspension for arbitrary foreign calls or introduce
async function annotations merely to settle the runtime representation early.
Distinguish optional independent execution, which may run inline, from work that
requires concurrency to make progress. An executor must reject the latter when it
cannot provide the required progress guarantee.

Atomic access, publication and permission to use ordinary data are separate.
Future memory-order APIs and audited shared-storage protocols must preserve that
distinction. Publication, protected observation, retirement and deferred reclamation
are useful later tests of the model; do not require immediate destruction of
retired storage or attempt general lock-free correctness proofs in the checker.
Validate trusted runtime protocols with native race instrumentation and bounded
interleaving exploration where practical, beyond checking final test values.

## Formal specification still needed

Before extending transfer or the runtime substantially, write a small set of
rules that works without mentioning Executor, Mutex or Channel:

- What identifies an access region, and how do reachable aliases establish overlap?
- Which authority is required by reading, writing, moving, destroying and replacing?
- Which preconditions permit loans and transfers between execution domains?
- How are transitive and latent effects inferred, bounded and checked through
  recursion, virtual dispatch, foreign calls and cleanup?
- How do ordinary values and opaque domains retain obligations without duplication?
- What evidence establishes completion, publication and authority restoration?
- How do failure, cancellation, branch joins and generation changes conserve that evidence?
- How are affinity and resource-specific concurrent guarantees represented after erasure?

Use existing summaries and storage receipts where their semantics fit. Do not
assume lifetime dependencies alone encode access effects, or that callback raw
addresses authenticate task storage. The boundary must retain initialization,
cleanup ownership and exact completion identity.

System.executor also remains blocked by VM handling of virtual capabilities with
native-only methods: eager lowering currently reaches callback-valued signatures
outside the VM subset. Resolve that independently of the authority model.

## Acceptance cases for the design

These describe required outcomes, not settled source syntax:

| Case | Required result |
| --- | --- |
| Two mutable aliases used sequentially in one domain | Accepted |
| Exclusive concurrent loan followed by caller access through another alias | Rejected until certified completion |
| Two concurrent read loans | Accepted while incompatible writes and destruction remain unavailable |
| Owner destruction may mutate an unsynchronized allocator also used by the caller | Rejected without exclusive authority or a verified synchronization guarantee |
| Access through an erased virtual contract | Preserves the same access and resource obligations |
| Completion returns authority and an owning result | Restores only matching permissions; never stale generations or consumed ownership |
| Two workers mutate partitions of one buffer | Accepted only with preserved evidence of nonoverlap; whole-buffer aliases remain restricted |
| Serialized handlers access shared mutable state | Requires certified nonoverlap, separately from thread affinity and suspension/reentry |
| A resource is destroyed in another domain | Checks that operation's cleanup policy, including concurrent or delegated release |
| Semaphore permits or atomic flags coordinate work | Grant no unrelated ordinary-memory authority |
| Retired storage remains visible to protected readers | Reclamation waits for the protocol's reader obligations, not only one task's join |

Extend these with nested aggregates, unknown aliases, opaque storage, wrappers,
failed submission, discarded results and cancellation. A useful design must make
these outcomes follow from common rules rather than per-abstraction exceptions.

## References for further investigation

These are design references, not a decision to adopt their full models:

- [Pony reference capabilities](https://tutorial.ponylang.org/capabilities/reference-capabilities.html): mutable aliasing within confinement and isolation across boundaries.
- [Swift region-based isolation, SE-0414](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md): contextual transfer using alias-connected regions.
- [Rust Send and Sync](https://doc.rust-lang.org/nomicon/send-and-sync.html) and [scoped threads](https://doc.rust-lang.org/std/thread/struct.Scope.html): transfer guarantees and bounded borrowed execution.
- [Go Mutex](https://go.dev/src/sync/mutex.go): the runtime synchronization contract.
- [Rust Waker](https://doc.rust-lang.org/std/task/struct.Waker.html) and [Tokio select cancellation safety](https://docs.rs/tokio/latest/tokio/macro.select.html): notification, registration and cancellation concerns.
- [Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html) and the local `references/zig` checkout: typed task adapters and alternative I/O/wait backends to investigate.
- [Rayon scoped work](https://docs.rs/rayon/latest/rayon/fn.scope.html): data-parallel partitioning and bounded task lifetimes to investigate.
- [Boost.Asio strands](https://www.boost.org/doc/libs/latest/doc/html/boost_asio/overview/core/strands.html): serialized execution as a separate design case.
- [Seastar SMP](https://docs.seastar.io/master/group__smp-module.html): shard-owned resources and cleanup policies to investigate.
- [ThreadSanitizer](https://clang.llvm.org/docs/ThreadSanitizer.html) and [Loom](https://docs.rs/loom/latest/loom/): runtime race instrumentation and bounded protocol exploration.
