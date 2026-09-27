-- A handle to storage for one T. The bytes are not a T until the owner
-- explicitly initializes the slot. The handle adds no per-slot state to the
-- allocation; an owning collection records occupancy in its own invariant.
MaybeUninit #(.t: Type) : Type = (
    .raw: RawPointer#(.t: t)
)

-- Low-level slot construction. The caller owns a suitably aligned allocation
-- with room for index and must keep its occupancy invariant separately.
trusted_uninit_slot#(.t: Type)(
    .allocation: $&Allocation,
    .index: UIntNative,
) -> (.slot: MaybeUninit#(.t: t)) := {
    offset ::= index * size_of(.type = t)
    byte ::= mutable_reference_offset#(.t: UInt8)(.base = allocation&.data, .elements = offset).reference
    slot = (.raw = raw_pointer#(.t: t)(.address = cast#(.to: UIntNative)(.value = byte)).raw)
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
