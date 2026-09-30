-- A handle to storage for one T. The bytes are not a T until the owner
-- explicitly initializes the slot. The handle adds no per-slot state to the
-- allocation; an owning collection records occupancy in its own invariant.
MaybeUninit #(.t: Type) : Type = (
    ._raw: RawPointer#(.t: t)
)

-- Checked selection publishes a storage handle, never an initialized T.
-- Private address state prevents callers from enlarging or redirecting it;
-- the existing dependency primitive retains the allocation's generation.
allocation_slot#(.t: Type)(
    .allocation: &Allocation,
    .index: UIntNative,
) -> (.slot: MaybeUninit#(.t: t)) := {
    address ::= _reference_offset_address(.address = allocation&.data.address, .elements = index, .element_size = size_of(.type = t)).result
    _require_allocation_slot_range(.allocation = allocation, .address = address, .size = size_of(.type = t), .alignment = alignment_of(.type = t))
    raw_slot :: MaybeUninit#(.t: t) = (._raw = raw_pointer#(.t: t)(.address = address).raw)
    anchored ::= depend_on#(.t: MaybeUninit#(.t: t))(.value = raw_slot, .on = allocation&.anchor).result
    slot = depend_on#(.t: MaybeUninit#(.t: t))(.value = anchored, .on = erase_reference#(.t: Allocation)(.base = allocation).reference).result
}

-- Address inspection is not a reference conversion or an occupancy proof.
uninit_slot_address#(.t: Type)(.slot: MaybeUninit#(.t: t)) -> (.address: UIntNative) := {
    address = slot._raw.address
}

-- Low-level slot construction. The caller owns a suitably aligned allocation
-- with room for index and must keep its occupancy invariant separately.
_trusted_uninit_slot#(.t: Type)(
    .allocation: &Allocation,
    .index: UIntNative,
) -> (.slot: MaybeUninit#(.t: t)) := {
    address ::= _reference_offset_address(.address = allocation&.data.address, .elements = index, .element_size = size_of(.type = t)).result
    slot = (._raw = raw_pointer#(.t: t)(.address = address).raw)
}

-- Only an owner that has established occupancy may turn a slot handle into
-- a normal reference. The handle itself never claims an initialized T. Borrow
-- provenance follows the Allocation's owned root and region anchor, so
-- replacing or ending the storage invalidates aliases to its former slots.
_trusted_uninit_borrow_ro#(.t: Type)(
    .allocation: &Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.reference: &t) := {
    mutable ::= trusted_establish_allocation_slot#(.t: t)(.allocation = allocation, .slot = slot._raw, .anchor = allocation&.anchor).reference
    reference = read_reference#(.t: t)(.base = mutable).reference
}

_trusted_uninit_borrow_rw#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.reference: $&t) := {
    reference = trusted_establish_allocation_slot#(.t: t)(.allocation = allocation, .slot = slot._raw, .anchor = allocation&.anchor).reference
}

-- Initializes an empty slot and transfers ownership into the allocation's
-- opaque domain. It must be called exactly once before reading that slot.
_trusted_uninit_write#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
    .value: t,
) -> () := {
    destination ::= trusted_establish_allocation_slot#(.t: t)(.allocation = allocation, .slot = slot._raw, .anchor = allocation&.anchor).reference
    trusted_opaque_move_in#(.t: t, .storage_type: Allocation)(
        .storage = allocation,
        .destination = destination,
        .source = ~value,
    )
}

-- Extracts a value known to occupy the slot. The caller must mark it empty
-- in its own invariant before another read or destruction is possible.
_trusted_uninit_take#(.t: Type)(
    .allocation: $&Allocation,
    .slot: MaybeUninit#(.t: t),
) -> (.value: t) := {
    source ::= trusted_establish_allocation_slot#(.t: t)(.allocation = allocation, .slot = slot._raw, .anchor = allocation&.anchor).reference
    value = trusted_opaque_move_out#(.t: t, .storage_type: Allocation)(
        .storage = allocation,
        .slot = source,
    )
}

-- Relocates a live opaque value into a distinct empty slot. Neither slot is
-- exposed as a T to the collection; the transient references exist only at
-- this trusted ownership transition.
_trusted_uninit_relocate#(.t: Type)(
    .source_allocation: &Allocation,
    .source: MaybeUninit#(.t: t),
    .destination_allocation: &Allocation,
    .destination: MaybeUninit#(.t: t),
) -> () := {
    source_ref ::= trusted_establish_allocation_slot#(.t: t)(.allocation = source_allocation, .slot = source._raw, .anchor = source_allocation&.anchor).reference
    destination_ref ::= trusted_establish_allocation_slot#(.t: t)(.allocation = destination_allocation, .slot = destination._raw, .anchor = destination_allocation&.anchor).reference
    trusted_opaque_relocate(.source = source_ref, .destination = destination_ref)
}
