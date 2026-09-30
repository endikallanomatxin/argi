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
storage authorization and creates the temporal allocation root.
`establish_inherited_storage(storage: AcquiredStorage, root)` consumes the same
authorization when attaching acquired bytes to an existing temporal domain.
The receipt is move-only. Establishment consumes it with `~storage`; forwarding
transfers it by move. A moved receipt cannot be inspected or established again. Its `deinit` discards
establishment authority, without releasing physical storage: this low-level
receipt owns no cleanup policy. The caller must establish a temporal owner or
arrange trusted physical cleanup. Read-only
`acquired_storage_address`, `acquired_storage_size`, and
`acquired_storage_alignment` borrow `&AcquiredStorage` and expose metadata without certifying
another region.

The caller of either establishment operation arranges physical cleanup with
the matching deallocator or temporal domain. A receipt does not certify an
arbitrary deallocator's behavior. Raw FFI release and low-level reference
construction remain trusted operations. An integer inspected before consumption
does not recreate the receipt or make released storage live again.

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

`allocation_slot<T>(allocation, index)` selects a complete, aligned slot inside
both the declared extent and the allocation's private certified extent. It
rejects arithmetic wrap and invalid bounds with a runtime trap. The result is
`MaybeUninit<T>`, not `&T` or `$&T`: selection cannot read, write, or destroy a
`T`. The handle's address is private, and its validity depends on the allocation
and backing anchor. Copies and forwarding retain those dependencies. Ending
the allocation or resetting its backing region invalidates the handle.
`uninit_slot_address<T>(slot)` exposes an integer address without certifying
initialized contents or granting a reference conversion.

### Slot authority and occupancy

Slot selection is repeatable: selecting the same index twice or copying a
`MaybeUninit<T>` produces handles to the same bytes. These handles carry range
and lifetime validity, not exclusive ownership or permission to initialize.
Consuming one handle does not revoke the others. Making the handle move-only
would therefore not, by itself, establish exclusive slot authority.

The storage owner controls occupancy through private state. Ordinary operations
request a transition from that owner; they cannot assert occupancy by supplying
a slot address or a boolean. The owner validates the selected range and the
current occupancy before invoking a trusted storage transition:

| Operation | Required state | Resulting state |
| --- | --- | --- |
| Initialize from a moved `T` | Vacant | Occupied by exactly one live `T` |
| Borrow a `T` | Occupied | Occupied; the reference depends on the owner and backing storage |
| Extract a `T` | Occupied | Vacant; ownership moves to the returned value |
| Destroy a `T` | Occupied | Vacant; the value's cleanup runs exactly once |

Replacement must account for the old value before publishing a new one.
Relocation requires a live source and a distinct vacant destination, transfers
the value once, and leaves the source vacant. A failed initialization must not
publish an occupied slot unless it leaves a valid live value there. Cleanup
visits occupied slots only.

Occupation can be represented by a collection invariant rather than a flag for
each element. `DynamicArray<T>` uses its initialized prefix: append publishes
the new length after moving in a value; pop removes an element from the prefix
and moves it out. Other owners may use different private representations.
Their trusted implementation must keep occupancy and stored values consistent.

References to contents must cease to be usable when extraction, destruction,
replacement, or relocation ends the referenced value's storage generation.
The owner may conservatively invalidate all element references for a structural
mutation. Copied storage handles do not override that invalidation or authorize
a second extraction. Range validity alone never proves that a live `T` remains.

> [!IMPLEMENTATION]
> `DynamicArray<T>` implements owner-controlled transitions using private
> length and trusted opaque operations. `allocation_slot<T>` only selects
> storage; there is no general ordinary initialization or extraction API for
> arbitrary allocation slots. Such an API must establish owner-controlled
> occupancy and content-reference invalidation before exposing reads.

Selecting bytes establishes no initialized `T`. `trusted_establish_allocation_slot`
checks the byte range and alignment but does not prove occupancy or a valid
representation. Its caller must prove initializedness before reading through
the returned reference; it is not an ordinary initialized-slot constructor.

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
