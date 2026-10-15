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

-- Explicit trusted establishment into raw storage. Callers must prove bounds,
-- alignment, and initialization before reading; an Allocation alone cannot.
_trusted_allocation_byte_ro(.allocation: &Allocation, .offset: UIntNative) -> (
    .reference : &UInt8
) := {
    address ::= _reference_offset_address(
        .address = allocation&.data.address, .elements = offset, .element_size = 1
    ).result
    raw ::= raw_pointer#(.t: UInt8)(.address = address).raw
    mutable ::= trusted_establish_allocation_slot#(.t: UInt8)(
        .allocation = allocation, .slot = raw, .anchor = allocation&.anchor
    ).reference
    reference = read_reference#(.t: UInt8)(.base = mutable).reference
}

_trusted_allocation_byte_rw(.allocation: $&Allocation, .offset: UIntNative) -> (
    .reference : $&UInt8
) := {
    address ::= _reference_offset_address(
        .address = allocation&.data.address, .elements = offset, .element_size = 1
    ).result
    raw ::= raw_pointer#(.t: UInt8)(.address = address).raw
    reference = trusted_establish_allocation_slot#(.t: UInt8)(
        .allocation = allocation, .slot = raw, .anchor = allocation&.anchor
    ).reference
}

-- Safety combines the allocation's owned-root dependency with its region
-- anchor. The slot address itself is raw and makes no initialization claim.
-- Runtime guards check alignment and both the declared and authenticated
-- byte extents. The allocator proves the physical region at establishment;
-- callers cannot expand it by editing the public receipt fields.
trusted_establish_allocation_slot#(.t: Type)(
    .allocation: &Allocation, .slot: RawPointer#(.t: t), .anchor: &Any
) -> (.reference: $&t) := {
    _require_allocation_slot_range(
        .allocation = allocation
        .address    = slot.address
        .size       = size_of(.type = t)
        .alignment  = alignment_of(.type = t)
    )
    reference = __trusted_reference_from_address#(.to: $&t)(.address = slot.address)
}

-- Range validation grants bytes only. It never asserts initialized contents
-- or publishes a reference, so checked slot selection can share these guards.
_require_allocation_slot_range(
    .allocation: &Allocation, .address: UIntNative, .size: UIntNative, .alignment: UIntNative
) -> () := {
    if address < allocation&._storage_address { abort }
    storage_offset ::= address - allocation&._storage_address

    if storage_offset > allocation&._storage_size { abort }
    if size > allocation&._storage_size - storage_offset { abort }
    if address < allocation&.data.address { abort }
    offset ::= address - allocation&.data.address

    if offset > allocation&.size { abort }
    if size > allocation&.size - offset { abort }
    if alignment == 0 { abort }
    if address % alignment != 0 { abort }
}
