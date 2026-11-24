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

The worker's cleanup can end structural subobjects of its owned input.
Following a stored reference crosses the boundary of that backing and
still requires preservation of any external loan. The current execution
ingress supports ordinary mutable loans of plain storage and bounded
erased capabilities. Extending exclusive lending to ordinary mutable
references to nonplain storage requires proving preservation at the
admitted loan's actual boundary.

## Returning an owned result

The worker checks the actual result before publishing it. A type-level
Transferable conformance can certify an owner whose cleanup and safety
obligations travel entirely with the value. The native output slot currently
carries the bytes and cleanup custody. Results with retained references or
other static storage evidence require a summary that can reestablish those
facts at the join, so publication rejects them today. The caller either
takes the occupied result by move or joins and runs its typed cleanup.

Reconstruct result facts from the worker's checked output effect. Instantiate
its input-relative facts from the input admitted at submission. Keep the
result effect with the authenticated output custody, including through
forwarding and receipt moves. A join can discharge an execution loan, while
dependencies retained by the result still have to be live for withdrawal or
discard. Fresh roots created by the worker need fresh identities in the
joining analysis. Every internal observation of the same root must use the
same identity, including the address and backing reference in an Allocation.
A returned input owner instead retains the identity established at submission.

The result type alone cannot recover either relation. Neither path requires
the identity of any erased deallocator implementation. The native output
slot retains its existing representation. Checked withdrawal and discard
need to consume the same custody, including on error paths where a worker
was accepted before submission returned a failure.

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

A receiver-only bound on the entire Deallocator interface is insufficient.
Building the dynamic-array fixture with `writes(self) isolated()` on that
interface rejects GeneralPurposeAllocator's conformance. Its release path
can traverse separately acquired bookkeeping and destroy nested allocations.
The receiver slot and its structural fields do not describe those accesses.
The POSIX page release is independently bounded at its private native
boundary because its callers hold custody of the mapping range.

A release guarantee for an erased capability must account for the storage
being released and for provider state reached by the operation. Widening a
receiver region to include all memory reachable from the provider would
also broaden the authority granted to callers, including callers with
exclusive loans. Local providers must remain usable with the same erased
interface even when their capabilities cannot fulfill the transfer proof.

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

## Allocation transfer boundary probe

The shared String submission fixture reaches execution loan collection when
run with a temporary bounded Deallocator interface and an unconditional
`Transferable#(Allocation)` hypothesis. It still fails with
"borrowed execution requires an authenticated reference target". The
hypothesis is only a probe and cannot be used as the Allocation guarantee.
The transfer proof and the admission of external loans are separate checks.
The latter needs to distinguish owner-relative backing observations from
references that require an external target.

Changing the worker to forward its String input to the result exposes a
different earlier check. The allocating output preparation call has an
unknown effect while execution loans are retained, and the caller reports
unknown effects while the allocator is shared. The result needs a checked
publication and cleanup summary even when the worker does no work beyond
moving the input. An unconditional input conformance does not provide that
summary.

Tracing the submission in that temporary core identifies two distinct
observations with missing targets. The erased default anchor (`&Any`)
arrives without any root or acquisition origin after summary instantiation.
The optional `&UInt8` backing observation arrives with an owned resource
root and acquisition origins but without a lexical or symbolic target.
The former needs preservation of immutable static backing through a
summary. The latter needs an owner-relative relationship whose validity
follows custody. A missing target by itself cannot justify either case.

With static anchor observations retained by summaries, the submission
probe now reports only the missing target of the optional backing
reference. In a disposable compiler build, bypassing that one check
for observations with acquisition origins let the existing shared String
worker run and return its length. This isolates the remaining inbound
gate. Acquisition origins alone cannot establish physical containment
or custody, so the compiler used for production keeps the check.

The forwarding worker still fails at output preparation in the same
experiment. Output custody and its latent cleanup need their own
verified effects before admitting a String round trip.

The structural Allocation probe reaches the raw data address check with
matching owner custody and a represented address field. The address field
retains its backing lifetime, but its forwarding recipe is validity-only.
That recipe may also describe scalar results derived from an address, so it
cannot restore an authenticated observation. Scalar address forwarding
needs evidence of the value relation independently of its lifetime.

With structural Allocation evidence and the temporary bounded release
interface, the allocation submission probe can also retain an external
slot alias at the sender. The worker consumes the allocation and returns
its size. After await and recovery of ordinary allocator authority, writing
through the old slot alias fails because the allocation root has ended.
Recovery is important in this probe: before it, the ordinary access check
can reject the write earlier because the allocator is still shared.

Inlining native output reservation into async_owned moves the unknown
effect diagnostic to the lexical _OwnedTaskOutput construction site.
The reservation import already publishes no_access(). The diagnostic is
attached to cleanup of that lexical owner on exit. Moving the reservation
between helpers cannot make destruction of an occupied output bounded.
The caller needs the latent cleanup effects of the actual result and must
check them at the point where output custody may be discharged.

The bounded-release probe also builds the sending function with an ordinary
CAllocator capture passed through string_with_length. With the same worker
and nominal String type, that submission fails at the static transfer
requirement. The shared variant runs the worker and updates a byte in its
owned backing. Thus the temporary access bound does not itself certify
transferability of the erased deallocator.

The same bounded-release Allocation probe rejects submission after the
caller writes zero to data.address. The rejection also holds when a
separate function writes the bits through a mutable reference to that field.
The nominal owner and its private cleanup bounds remain present, but they
do not authenticate a replacement public data address.
