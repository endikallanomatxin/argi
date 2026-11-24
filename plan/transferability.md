# Ownership transfer and static safety evidence

The type defines the interface and physical representation. Value facts describe
guarantees of the current contents. Safety state authorizes the operation at
the point where ownership crosses an execution boundary.

A nominal type's owner may publish Transferable when the guarantee holds for
every valid value of that type. The guarantee covers use and eventual cleanup in
the receiving execution. Temporal dependencies, pending loans and cleanup
ownership remain separate obligations. A type guarantee grants no permission to
transfer a reference to the type.

The nominal owner may instead declare StructurallyTransferable. This vouches
that use and cleanup rely on the guarantees of the current fields or active
payload. The checker still proves each component transferable, so values
with a retained local and a retained concurrent handle can differ. String
uses this conformance to delegate its proof to its Allocation and shape.

Virtual construction can carry static evidence about the actual captured
capability, including its receiver permission and retained dependencies. Two
handles for the same contract can have different evidence. Derive aggregate
evidence from the current components. At joins, retain guarantees supported by
every alternative. Use the existing reference-write and post-state machinery to
replace evidence or drop it when the affected contents cannot be resolved.

Represent summary requirements as bounded conjunctions of input guarantees.
Check ownership transfer before native submission and preserve cleanup through
failure, completion and result transport. Evidence is compiler state and takes
no space in values, virtual tables or specialization keys.

Validate the same String type and submission specialization with a shareable
deallocation capability and with a local provider. Cover forwarding, joins,
alias replacement, stale dependencies, outstanding loans and failure cleanup.
Measure compiler time and peak memory alongside generated code and specialization
counts. The existing sequential reference-content regressions remain separate
obligations.

## Native input handoff

The current task adapter copies its input bytes before attempting to start the
worker. For an owning input, treat this copy as provisional until submission
succeeds. A failed start discards the provisional bytes and the submitting
scope cleans up its original value. An accepted start authorizes exactly one
worker to consume the copy. The submitting scope then retires its original
cleanup obligation without invoking it. Inline submission follows the same
ownership rule, including when the worker has already completed on return.

The acceptance proof must originate at the authenticated native submission.
Carry it through TaskRequest and executor results so a provider cannot
manufacture acceptance, submit a request twice, or disguise acceptance as a
failure that would reactivate sender cleanup. The receipt retains execution
loans until completion. Its lifetime and the actual result's transfer evidence
are separate from ownership of the request input.

## Returning an owned result

The worker checks the actual result before publishing it. A type-level
Transferable conformance can certify an owner whose cleanup and safety
obligations travel entirely with the value. The native output slot currently
carries the bytes and cleanup custody. Results with retained references or
other static storage evidence require a summary that can reestablish those
facts at the join, so publication rejects them today. The caller either
takes the occupied result by move or joins and runs its typed cleanup.

## Erased deallocation capability

Deallocator selects evidence using the full captured reference type. A local
provider can implement the contract for an ordinary mutable reference and a
concurrent provider for a concurrent reference. Both use the same public
virtual type. A call reads the descriptor and applies the selected operation
with its captured authority.

Resource-owning types also need a compositional cleanup guarantee. In
particular, proving that the current Allocation has a suitable deallocator
requires accounting for its backing mode and anchor. A recursive field walk
cannot establish that the destructor confines itself to those capabilities.
Keep that destructor obligation explicit and validate the dependency when
applying the proof at the execution boundary.

A virtual implementation must prove the access guarantee published by its
interface. A caller combines that guarantee with the authority and temporal
dependencies retained by the handle. A transfer proof does not require a
concrete method identity. Selected methods may improve local precision, while
an unbounded interface remains insufficient when access authorization depends
on a bound. Forwarding and cleanup summaries carry the same requirements.

Transferability, temporal validity, storage identity and access authority
answer distinct questions. An unknown target may prevent proving disjoint
access while leaving a retained transfer guarantee intact. A live backing
root proves neither transferability nor synchronization. An exclusive loan
temporarily restricts the sender and returns authority on completion.
Ownership transfer moves cleanup responsibility. Concurrent sharing grants
simultaneous access through a verified interface. Use the corresponding
evidence at each boundary and keep it out of runtime layouts and
specialization keys.

### Deallocator access bounds

The local/shared String cleanup fixture accepts both CAllocator captures
under an experimental `writes(self) isolated()` interface once the private
C heap release declares audited isolation. The same experiment rejects
Memory at its native page release. Temporarily marking that import
`no_access() isolated()` allows the fixture to run, but the annotation
alone cannot prove that the supplied raw range is under release custody.
The platform imports therefore keep their conservative footprints.

The general-purpose slot reuse fixture still rejects the experimental
interface even with the page annotation. Its general-purpose provider
touches dynamically addressed metadata, and its tracking adapter accesses
a provider behind a stored reference. Neither effect follows from a bound
on receiver storage.

Keep the acquired block's release effect separate from access to provider
state. The former is authorized by Allocation's custody and acquisition bounds.
The latter must use the authority retained by the virtual handle, including
exclusive access for a local provider or trusted concurrent access for a
shared provider. A receiver bound alone cannot account for either native
release or a provider's separately stored metadata.

### Transfer admission after isolation

Running the String submission fixture
`tests/feature_tests/concurrency/411X_owned_task_string_unbounded_cleanup`
against a temporary core with the experimental deallocator and page release
bounds reaches two independent rejections. The structural transfer proof
cannot certify Allocation, and execution lending rejects its optional
backing-reference payload. The production core continues to reject the
earlier, unbounded cleanup call.

The optional reference observes the bytes owned by Allocation. A proof for
this field must relate it to the backing that moves with the owner. Treating
every reference in a choice as independently lendable would miss this
distinction. The anchor and erased deallocator can retain external storage,
so their validity and access obligations still need proof at submission
and transportation back through an owned result.

## Release interface experiment

The move-only release request experiment grouped the raw bounds without
proving a relationship to the allocation or its provider. The current
interface keeps release custody in Allocation. Its destructor supplies the
original bounds to the retained deallocator. Provider guarantees need to
describe the effect of that release independently of any runtime packet.

The local/shared String cleanup fixture
`tests/feature_tests/concurrency/378_shared_string_cleanup` measures the
effect of the move-only release request in `7d27742fd`. The same Debug
compiler built the same fixture with the previous and current core trees on
Linux x86-64. Each configuration used five alternating builds with
`--no-cache --frontend-jobs 1 --stats --emit-llvm` and a subsequent successful
execution. The optimized measurement added `--release`.

| Metric | Debug before | Debug after | Release before | Release after |
| --- | ---: | ---: | ---: | ---: |
| Median build wall time, seconds | 1.00 | 0.98 | 1.58 | 1.62 |
| Median peak RSS, KiB | 140864 | 140704 | 146584 | 146656 |
| Median GlobalSafety time, ms | 46.228 | 46.366 | 45.809 | 47.075 |
| Executable text, bytes | 134219 | 135843 | 55193 | 55473 |
| Executable file, bytes | 165120 | 165472 | 86392 | 86656 |
| Generic bodies built | 89 | 91 | 89 | 91 |
| LLVM functions reported | 117 | 122 | 97 | 100 |

The generic-body count includes bodies that did not reach code generation.
These figures measure the retired release request and its cleanup. A separate
measurement needs to exercise ownership transfer with the same compilation
specialization and different value evidence.

## Cost of structural transfer evidence

Build the retained virtual cleanup fixture
`tests/feature_tests/concurrency/413_owned_task_retained_virtual_cleanup`
with its original `StructurallyTransferable#(Owner)` declaration and with
`Transferable#(Owner)` in its place. An x86-64 Linux run on `40a26d847`
used five alternating builds per declaration, with one frontend worker,
`--release --no-cache --stats --emit-llvm`, and ran each executable.

| Metric | Unconditional | Structural |
| --- | ---: | ---: |
| Median wall time, seconds | 1.88 | 1.88 |
| Median peak RSS, KiB | 146592 | 146672 |
| Median safety time, ms | 46.219 | 46.438 |
| Generic bodies built | 126 | 126 |
| LLVM functions reported | 117 | 117 |
| Executable text, bytes | 51538 | 51532 |

Both emitted one owned task worker with the same symbol and 174-byte
machine code size. This comparison measures the structural proof for an
owner retaining a virtual handle. The String round trip remains a separate
workload.
