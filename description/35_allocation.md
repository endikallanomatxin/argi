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

`Allocation.data` is a non-dereferenceable `RawPointer<UInt8>`. It records a
size and alignment, a temporal anchor, and an erased deallocator. The low-level
`Memory.map_pages` capability records the page-rounded physical size;
`PageAllocator` adapts that receipt so its `Allocation` records the caller's
requested size and alignment.

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

`System` exposes `$&Memory` and `$&PageAllocator` capabilities. `Memory` is
initialized from the operating system and maps or unmaps page-rounded physical
storage. The operating-system mapping bindings are private implementation
details; programs receive the capability rather than general FFI access.
`PageAllocator(memory)` implements the general `Allocator` interface and
returns an `Allocation` that records the caller's requested size and alignment.

Allocating functions take an allocator argument explicitly. There is no
implicit default allocator. `GeneralPurposeAllocator` receives a backing
allocator and acquires both its storage blocks and metadata through it; it
makes no direct operating-system calls. A program selects its allocator, for
example:

```rg
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
```

The backing allocator is chosen by the program, subject to allocator-summary
compatibility: a `GeneralPurposeAllocator` backed by an `ArenaAllocator` is
currently incompatible. The canonical `PageAllocator` →
`GeneralPurposeAllocator` → `ArenaAllocator` chain works. This makes the
allocation chain visible and composable. The current general-purpose allocator
groups small requests by power-of-two size class. Its internal `_bucket_size`
is a 4096-byte chunk size, independent of the operating system's page size:
one chunk holds metadata and the other holds aligned slots. Each bucket has a
bitmap of live slots and a search cursor; freeing a slot lowers the cursor when
necessary, so allocations find the first free bit without skipping holes. A
completely empty bucket returns its backing storage. Each allocation establishes
a fresh temporal root, including when it reuses an address. Requests larger
than half the chunk size go directly to the backing allocator and are tracked
separately.
`has_live_allocations()` reports whether either kind remains live; repeated
frees of tracked allocations abort. Thread synchronization and stack-trace
diagnostics are not provided yet.

`CAllocator(.ffi = system.ffi)` remains available for explicit libc storage
interoperation. Public `malloc`, `aligned_alloc`, and `free` wrappers also
require `.ffi`; their raw `extern` declarations are private. This makes the
language-level libc allocation APIs capability-gated. Compiler-generated
error-trace allocation in codegen still calls libc `malloc`/`free`; handling
that path is a separate outstanding runtime task, not part of these public
wrappers or allocator capabilities.

`ArenaAllocator` receives a backing allocator as a virtual `Allocator` and
stores each backing `Allocation` receipt in the corresponding linked block
header. It allocates no separate metadata and does not use a collection to
track blocks. `reset` ends the shared arena lifetime and releases its blocks
through those receipts. Individual child deallocations do not release a block.

Using an allocator and implementing `deinit()` does not make a type implicitly
copyable. Ownership, copying, and borrowed views remain separate concerns; see
`32_copying_behaviour.md` and `38_safety_model.md`.
