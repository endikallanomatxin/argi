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
    _require_allocation_alignment(.alignment = alignment)
    physical_alignment ::= alignment
    pointer_alignment ::= alignment_of(.type = UIntNative)
    if physical_alignment < pointer_alignment { physical_alignment = pointer_alignment }
    physical_size ::= size
    if physical_size == 0 { physical_size = 1 }
    remainder ::= physical_size % physical_alignment
    if remainder != 0 {
        padding ::= physical_alignment - remainder
        physical_size = physical_size + padding
        if physical_size < size {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }
    address ::= aligned_alloc(.alignment = physical_alignment, .size = physical_size, .ffi = self&.ffi).address
    if address == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = address, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
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
)

-- Compiler-owned temporal boundary used after a physical allocator has
-- returned backing storage. The Allocation value owns the new root; its data
-- field only depends on it.
establish_allocation(
    .storage: UIntNative,
    .size: UIntNative,
    .alignment: UIntNative,
    .deallocator: Virtual#(.abstract: Deallocator),
) -> (.allocation: Allocation) := {
    allocation = (
        .data = raw_pointer#(.t: UInt8)(.address = storage).raw,
        .size = size,
        .alignment = alignment,
        .anchor = cast#(.to: &Any)(.value = &allocation_static_anchor),
        .deallocator = deallocator,
    )
}

deinit(
    .self: $&Allocation,
) -> () := {
    deallocate(.self = $&self&.deallocator, .data = self&.data, .size = self&.size, .alignment = self&.alignment)
}

-- Explicit trusted establishment into raw storage. Callers must prove bounds,
-- alignment, and initialization before reading; an Allocation alone cannot.
_trusted_allocation_byte_ro(.allocation: &Allocation, .offset: UIntNative) -> (.reference: &UInt8) := {
    raw ::= raw_pointer#(.t: UInt8)(.address = allocation&.data.address + offset).raw
    mutable ::= establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = raw, .anchor = allocation&.anchor).reference
    reference = read_reference#(.t: UInt8)(.base = mutable).reference
}

_trusted_allocation_byte_rw(.allocation: $&Allocation, .offset: UIntNative) -> (.reference: $&UInt8) := {
    raw ::= raw_pointer#(.t: UInt8)(.address = allocation&.data.address + offset).raw
    reference = establish_allocation_slot#(.t: UInt8)(.allocation = allocation, .slot = raw, .anchor = allocation&.anchor).reference
}

-- Safety combines the allocation's owned-root dependency with its region
-- anchor. The slot address itself is raw and makes no initialization claim.
establish_allocation_slot#(.t: Type)(
    .allocation: &Allocation,
    .slot: RawPointer#(.t: t),
    .anchor: &Any,
) -> (.reference: $&t) := {
    reference = cast#(.to: $&t)(.value = slot.address)
}
