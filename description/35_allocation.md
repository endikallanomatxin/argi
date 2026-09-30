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
    ._storage_address: UIntNative
    ._storage_size: UIntNative
    ._storage_alignment: UIntNative
    ._release_size: UIntNative
)
```

The private storage fields retain the address, extent, and alignment certified
by the allocator at establishment. Public receipt fields describe a requested
range; changing them cannot enlarge the certified region. Slot establishment
checks containment in both ranges and the target type's alignment. Cleanup
uses the original storage fields, so editing public data, size, or alignment
cannot change the storage arguments passed to release. The public deallocator
can still be replaced by an allocator adapter; that adapter remains responsible
for honoring the acquisition's release contract. These fields are private to
bundled core, rather than a general proof that an arbitrary address
was acquired. A granted prefix can be smaller than its acquisition; cleanup
retains the acquisition's original extent and alignment.

### Acquisition receipts

`AcquiredStorage` certifies a successful physical acquisition, independently
of any temporal owner or initialized `T`. Its address, size, and alignment are
private to bundled core. `acquire_heap_storage(size, alignment, ffi)` and
`acquire_page_storage(memory, size, alignment)` return `Errable<AcquiredStorage>`.
Neither publishes a receipt on failure. A zero-size request is valid and grants
no readable bytes, even when acquisition reserves heap or page padding.

`establish_allocation(storage: AcquiredStorage, size, alignment, deallocator,
anchor)` checks that the requested prefix fits the acquired extent and that
its address satisfies the requested alignment. It consumes the acquisition's
shared storage authorization and creates the temporal allocation root.
`establish_inherited_storage(storage: AcquiredStorage, root)` consumes the same
authorization when attaching acquired bytes to an existing temporal domain.
The receipt is copyable, but copies and forwarding wrappers alias one
authorization; they cannot establish that acquisition twice. Read-only
`acquired_storage_address`, `acquired_storage_size`, and
`acquired_storage_alignment` expose acquisition metadata without certifying
another region.

The caller of either establishment operation arranges physical cleanup with
the matching deallocator or temporal domain. A receipt does not certify an
arbitrary deallocator's behavior. Raw FFI release and low-level reference
construction remain trusted operations. Receipt inspection after consumption
does not make the storage live again.

`trusted_establish_allocation` is the explicit integer-address boundary for
suballocators and integrations outside those acquisition factories. Its caller proves that
the address and extent describe acquired, live storage and that the deallocator
matches that acquisition. Its runtime guards reject invalid alignment and
address-range wrap. Suballocators certify only the selected child range and
retain a temporal anchor to the backing region. An ordinary caller must obtain
an allocation through `Allocator`; supplying an integer to the trusted boundary
does not discharge the acquisition obligation. The analogous integer-address
operation for an existing domain is `trusted_establish_inherited_storage`.

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
