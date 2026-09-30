# Allocators and raw storage

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

A zero-size allocation provides no accessible bytes. An allocator may reserve
internal padding for it, but that padding does not authorize a nonzero-size
slot. The allocation may still be released normally.

## Raw storage and typed slots

`Allocation.data` is a non-dereferenceable `RawPointer<UInt8>`. An
`Allocation` records size, alignment, a temporal anchor, and the means to
release its storage. Its type alone does not determine whether the allocation
has an independent lifetime or inherits one from an arena.
The raw storage is not an initialized `T`; creating a safe typed reference
requires a checked establishment step.

```rg
Allocation : Type = (
    .data: RawPointer#(.t: UInt8)
    .size: UIntNative
    .alignment: UIntNative
    .anchor: &Any
    .deallocator: Virtual#(.abstract: Deallocator)
)
```

Higher-level values such as `String` and `DynamicArray<T>` keep their own
occupancy and length invariants. `MaybeUninit<T>` identifies a typed slot
without claiming whether it is occupied. It has no occupancy flag and does
not expose a `T`; only initialization establishes a live value. A container
must track which slots contain live values. Its private helpers initialize a
vacant slot through the trusted opaque move-in operation or extract an
occupied slot through opaque move-out. `DynamicArray<T>` keeps `[0, length)`
occupied and `[length, capacity)` vacant. Its movement operations pass slot
handles to trusted relocation; normal references are formed only after
checking `index < length`. Empty slots cannot be exposed as `&T` or `$&T`.

Trusted slot operations establish typed references only when the storage is
large enough, correctly aligned, and contains a valid `T`. Their validity
remains tied to the allocation and its anchor. Releasing or resetting storage
invalidates those references.

## Allocator composition

`System` exposes `$&Memory` and `$&PageAllocator` capabilities. `Memory` maps
and unmaps operating-system pages. `PageAllocator(memory)` implements the
general `Allocator` interface, returning an `Allocation` whose size and
alignment match the caller's request.

Allocating functions take an allocator argument explicitly. There is no
implicit default allocator. `GeneralPurposeAllocator` receives a backing
allocator. A program selects its allocator, for example:

```rg
assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
```

Allocators compose: a `PageAllocator` may back a
`GeneralPurposeAllocator`, which may in turn back an `ArenaAllocator`.
An independent allocation establishes a fresh validity root: its
`Allocation` value ends that root, and safe references established from its
data depend on it.
Individual allocations from a general-purpose allocator have distinct
lifetimes, including when an address is reused.

An arena value instead ends one root shared by its allocations. Their anchors
and the references established from them depend on that root. Reset ends the
shared lifetime and releases backing storage; later allocations belong to a
new generation, so references into the old one remain stale. Releasing one
child does not release a whole arena block.

`CAllocator(.ffi = system.ffi)` supports explicit libc storage
interoperation. Public `malloc`, `aligned_alloc`, and `free` wrappers also
require `.ffi`.

Fixed-size error tracers allocate their buffers through an explicit allocator
during initialization. Propagation adds bounded context without allocation.

Using an allocator and implementing `deinit()` does not make a type implicitly
copyable. Cleanup, copying, and borrowed views remain separate concerns.
