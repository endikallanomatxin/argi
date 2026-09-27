-- A handle to storage for one T. The bytes are not a T until the owner
-- explicitly initializes the slot. The handle adds no per-slot state to the
-- allocation; an owning collection records occupancy in its own invariant.
MaybeUninit #(.t: Type) : Type = (
    .raw: RawPointer#(.t: t)
)

-- Low-level slot construction. The caller owns a suitably aligned allocation
-- with room for index and must keep its occupancy invariant separately.
trusted_uninit_slot#(.t: Type)(
    .allocation: &Allocation,
    .index: UIntNative,
) -> (.slot: MaybeUninit#(.t: t)) := {
    offset ::= index * size_of(.type = t)
    address ::= cast#(.to: UIntNative)(.value = allocation&.data) + offset
    slot = (.raw = raw_pointer#(.t: t)(.address = address).raw)
}

-- Only an owner that has established occupancy may turn a slot handle into
-- a normal reference. The handle itself never claims an initialized T. Borrow
-- provenance follows the backing data generation, so replacing the allocation
-- invalidates aliases to its former slots.
trusted_uninit_borrow_ro#(.t: Type)(
    .allocation: &Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.reference: &t) := {
    storage_root ::= read_reference#(.t: UInt8)(.base = allocation&.data).reference
    mutable ::= establish_inherited_reference#(.t: t)(
        .raw = slot.raw,
        .root = cast#(.to: &Any)(.value = storage_root),
    ).reference
    reference = read_reference#(.t: t)(.base = mutable).reference
}

trusted_uninit_borrow_rw#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.reference: $&t) := {
    storage_root ::= read_reference#(.t: UInt8)(.base = allocation&.data).reference
    reference = establish_inherited_reference#(.t: t)(
        .raw = slot.raw,
        .root = cast#(.to: &Any)(.value = storage_root),
    ).reference
}

-- Initializes an empty slot and transfers ownership into the allocation's
-- opaque domain. It must be called exactly once before reading that slot.
trusted_uninit_write#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
    .value: t,
) -> () := {
    destination ::= establish_inherited_reference#(.t: t)(
        .raw = slot.raw,
        .root = cast#(.to: &Any)(.value = allocation),
    ).reference
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage = allocation,
        .destination = destination,
        .source = ~value,
    )
}

-- Extracts a value known to occupy the slot. The caller must mark it empty
-- in its own invariant before another read or destruction is possible.
trusted_uninit_take#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.value: t) := {
    source ::= establish_inherited_reference#(.t: t)(
        .raw = slot.raw,
        .root = cast#(.to: &Any)(.value = allocation),
    ).reference
    value = trusted_opaque_move_out#(.t: t, .storage_type: Allocation)(
        .storage = allocation,
        .slot = source,
    )
}

-- Relocates a live opaque value into a distinct empty slot. Neither slot is
-- exposed as a T to the collection; the transient references exist only at
-- this trusted ownership transition.
trusted_uninit_relocate#(.t: Type)(
    .source_allocation: &Allocation,
    .source: MaybeUninit#(.t: t),
    .destination_allocation: &Allocation,
    .destination: MaybeUninit#(.t: t),
) -> () := {
    source_root ::= read_reference#(.t: UInt8)(.base = source_allocation&.data).reference
    destination_root ::= read_reference#(.t: UInt8)(.base = destination_allocation&.data).reference
    source_ref ::= establish_inherited_reference#(.t: t)(
        .raw = source.raw,
        .root = cast#(.to: &Any)(.value = source_root),
    ).reference
    destination_ref ::= establish_inherited_reference#(.t: t)(
        .raw = destination.raw,
        .root = cast#(.to: &Any)(.value = destination_root),
    ).reference
    trusted_opaque_relocate(.source = source_ref, .destination = destination_ref)
}
