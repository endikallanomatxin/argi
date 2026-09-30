..out_of_memory

Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory)))
)

-- Every implementation checks this low-level precondition before acquiring
-- storage. A zero or non-power-of-two alignment is a programming error.
_require_allocation_alignment(.alignment: UIntNative) -> () := {
    if alignment == 0 { abort }
    remaining ::= alignment
    while remaining % 2 == 0 {
        remaining = remaining / 2
    }
    if remaining != 1 { abort }
}

Deallocator : Abstract = (
    deallocate(.self: $&Self, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> ()
)

-- This compatibility overload is for callers requesting byte storage. The
-- virtual allocator boundary always receives size and alignment.
allocate(.self: $&Allocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    result = allocate(.self = self, .size = size, .alignment = 1)
}

allocate#(.t: Type)(.self: $&Allocator, .count: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    element_size ::= size_of(.type = t)
    bytes ::= element_size * count
    if element_size != 0 and bytes / element_size != count {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = allocate(.self = self, .size = bytes, .alignment = alignment_of(.type = t))
}

allocate#(.t: Type)(.self: $&Allocator) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    result = allocate#(.t: t)(.self = self, .count = 1)
}

CAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
)

init(.p: $&CAllocator, .ffi: $&ForeignFunctionInterface) -> () := {
    p&.ffi = ffi
}

allocate(.self: $&CAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    acquired ::= acquire_heap_storage(.size = size, .alignment = alignment, .ffi = self&.ffi)
    match acquired {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ storage {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation(.storage = ~storage, .size = size, .alignment = alignment, .deallocator = deallocator)
            result = ..ok ~allocation
        }
    }
}

deallocate(.self: $&CAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    free(.address = data.address, .ffi = self&.ffi)
}

CAllocator implements Allocator
CAllocator implements Deallocator

-- Heap storage needs no region lifetime beyond its own root. This initialized
-- marker gives the uniform anchor field a stable lifetime without making the
-- allocator object a shared validity root for unrelated allocations.
allocation_static_anchor :: UInt8 = 0

Allocation : Type = (
    --
    -- Contiguous allocated storage together with the deallocator required for
    -- its physical cleanup.
    --
    -- The concrete allocate operation determines its temporal facts. A heap
    -- allocation can own a fresh root, while region-backed storage can depend
    -- on a shared root without owning an individual one.
    --
    -- The nominal type does not imply ownership, element type, shape, or view
    -- semantics.
    --
    -- `Allocation` is move-only. A higher-level owner may provide its own
    -- explicit `copy()` that acquires independent storage.
    --
    .data      : RawPointer#(.t: UInt8)
    .size      : UIntNative
    .alignment : UIntNative
    -- The heap uses a static marker; arena children point at ArenaDomain.
    .anchor    : &Any
    .deallocator : Virtual#(.abstract: Deallocator)
    -- Allocator-authenticated bounds. Public receipt fields can restrict a
    -- request, but cannot enlarge this region or change the address, size,
    -- or alignment passed to physical cleanup.
    ._storage_address: UIntNative
    ._storage_size: UIntNative
    ._storage_alignment: UIntNative
    -- A granted prefix may be smaller than the acquisition being released.
    ._release_size: UIntNative
)

-- Compiler-owned temporal boundary used after a physical allocator has
-- returned backing storage. Each allocation owns a fresh temporal root.
-- Region-backed storage also retains the generation of its backing anchor.
-- The allocator certifies acquisition and containment; these scalar arguments
-- are not themselves evidence that storage was acquired. Private bounds keep
-- that assertion intact when the receipt crosses ordinary caller code.
trusted_establish_allocation(
    .storage: UIntNative,
    .size: UIntNative,
    .alignment: UIntNative,
    .deallocator: Virtual#(.abstract: Deallocator),
    .anchor: &Any = erase_reference#(.t: UInt8)(.base = &allocation_static_anchor).reference,
) -> (.allocation: Allocation) := {
    _require_allocation_alignment(.alignment = alignment)
    if storage == 0 and size != 0 { abort }
    if storage % alignment != 0 { abort }
    if storage + size < storage { abort }
    allocation = (
        .data = raw_pointer#(.t: UInt8)(.address = storage).raw,
        .size = size,
        .alignment = alignment,
        .anchor = anchor,
        .deallocator = deallocator,
        ._storage_address = storage,
        ._storage_size = size,
        ._storage_alignment = alignment,
        ._release_size = size,
    )
}

-- Normal establishment requires an acquisition receipt. Its private bounds
-- survive copying and forwarding; the compiler consumes the address's shared
-- authorization through the same transfer contract as trusted establishment.
establish_allocation(
    .storage: AcquiredStorage,
    .size: UIntNative,
    .alignment: UIntNative,
    .deallocator: Virtual#(.abstract: Deallocator),
    .anchor: &Any = erase_reference#(.t: UInt8)(.base = &allocation_static_anchor).reference,
) -> (.allocation: Allocation) := {
    _require_allocation_alignment(.alignment = alignment)
    if size > storage._size { abort }
    if storage._address % alignment != 0 { abort }
    allocation = trusted_establish_allocation(.storage = storage._address, .size = size, .alignment = alignment, .deallocator = deallocator, .anchor = anchor).allocation
    allocation._release_size = storage._size
    allocation._storage_alignment = storage._alignment
}

deinit(
    .self: $&Allocation,
) -> () := {
    -- Cleanup may touch backing metadata; an ended region cannot be released.
    live ::= self&.anchor&
    data ::= raw_pointer#(.t: UInt8)(.address = self&._storage_address).raw
    deallocate(.self = $&self&.deallocator, .data = data, .size = self&._release_size, .alignment = self&._storage_alignment)
}

-- Explicit trusted establishment into raw storage. Callers must prove bounds,
-- alignment, and initialization before reading; an Allocation alone cannot.
_trusted_allocation_byte_ro(.allocation: &Allocation, .offset: UIntNative) -> (.reference: &UInt8) := {
    address ::= _reference_offset_address(.address = allocation&.data.address, .elements = offset, .element_size = 1).result
    raw ::= raw_pointer#(.t: UInt8)(.address = address).raw
    mutable ::= establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = raw, .anchor = allocation&.anchor).reference
    reference = read_reference#(.t: UInt8)(.base = mutable).reference
}

_trusted_allocation_byte_rw(.allocation: $&Allocation, .offset: UIntNative) -> (.reference: $&UInt8) := {
    address ::= _reference_offset_address(.address = allocation&.data.address, .elements = offset, .element_size = 1).result
    raw ::= raw_pointer#(.t: UInt8)(.address = address).raw
    reference = establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = raw, .anchor = allocation&.anchor).reference
}

-- Safety combines the allocation's owned-root dependency with its region
-- anchor. The slot address itself is raw and makes no initialization claim.
-- Runtime guards check alignment and both the declared and authenticated
-- byte extents. The allocator proves the physical region at establishment;
-- callers cannot expand it by editing the public receipt fields.
establish_allocation_slot#(.t: Type)(
    .allocation: &Allocation,
    .slot: RawPointer#(.t: t),
    .anchor: &Any,
) -> (.reference: $&t) := {
    if slot.address < allocation&._storage_address { abort }
    storage_offset ::= slot.address - allocation&._storage_address
    if storage_offset > allocation&._storage_size { abort }
    if size_of(.type = t) > allocation&._storage_size - storage_offset { abort }
    if slot.address < allocation&.data.address { abort }
    offset ::= slot.address - allocation&.data.address
    if offset > allocation&.size { abort }
    if size_of(.type = t) > allocation&.size - offset { abort }
    if slot.address % alignment_of(.type = t) != 0 { abort }
    reference = __trusted_reference_from_address#(.to: $&t)(.address = slot.address)
}
