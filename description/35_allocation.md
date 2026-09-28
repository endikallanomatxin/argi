## Allocators and raw storage

An `Allocator` reserves storage by size and alignment. It does not construct
values or know their type:

```rg
Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative, .alignment: UIntNative)
        -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory)))
)
```

The low-level alignment must be a nonzero power of two. Implementations check
this precondition and `abort` if it is violated; an invalid alignment is not
`..out_of_memory`. The typed `allocate#(.t: T)(.count)` helper computes the
size and alignment from `T`, checks multiplication overflow, and still returns
raw `Allocation` storage. A zero-size allocation is valid. Allocation failure
returns no storage, safe reference, or cleanup obligation.

`Allocation.data` is a non-dereferenceable `RawPointer<UInt8>`. The allocation
also records the requested size and alignment, a temporal anchor, and an erased
deallocator. Physical rounding is an implementation detail of the allocator.

```rg
Allocation : Type = (
    .data: RawPointer#(.t: UInt8)
    .size: UIntNative
    .alignment: UIntNative
    .anchor: &Any
    .deallocator: Virtual#(.abstract: Deallocator)
)
```

Higher-level owners such as `String` and `DynamicArray<T>` keep their own
occupancy and length invariants. `MaybeUninit<T>` identifies a suitable slot;
only initialization establishes a live `T`. Trusted core helpers can establish
references to slots under the owner's bounds, alignment, and occupancy
invariants. Safety ties those references to the allocation's root and anchor,
so releasing or resetting the storage invalidates them.

`PageAllocator` obtains anonymous virtual-memory mappings and releases them
with `munmap`. It maps extra pages for requests aligned beyond the page size,
then unmaps the unused edges. `GeneralPurposeAllocator` is the default for
`System` and for implicit `Allocator` parameters. It groups small requests by
power-of-two size class in page-backed buckets. Each bucket has a bitmap of
live slots; freed slots are not reused while that bucket remains mapped.
Requests larger than half a page go directly to page mappings and are tracked
separately. `has_live_allocations()` reports whether either kind of allocation
remains live; repeated frees of tracked allocations abort. Both allocators preserve
the requested size and alignment in `Allocation`. The current implementation
uses POSIX mappings; it does not yet provide Zig's stack-trace diagnostics or
thread synchronization.

`CAllocator` remains available for storage acquired from libc, including
explicit `malloc`/`free` interoperation. `ArenaAllocator` uses libc for its
physical blocks and a caller-supplied allocator for block metadata; `reset`
ends the shared arena lifetime and releases the blocks. Individual child
deallocations do not release a block.

Using an allocator and implementing `deinit()` does not make a type implicitly
copyable. Ownership, copying, and borrowed views remain separate concerns; see
`32_copying_behaviour.md` and `38_safety_model.md`.
