# Ownership transfer and static safety evidence

The type defines the interface and physical representation. Value facts describe
guarantees of the current contents. Safety state authorizes the operation at
the point where ownership crosses an execution boundary.

A nominal type's owner may publish Transferable when the guarantee holds for
every valid value of that type. The guarantee covers use and eventual cleanup in
the receiving execution. Temporal dependencies, pending loans and cleanup
ownership remain separate obligations. A type guarantee grants no permission to
transfer a reference to the type.

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
