unsafe_allocation := import ("../../_support/unsafe_allocation")

SlotProtocol: Abstract = (
    put(.self: &Self, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked) -> () where {
        retains(storage, value)
    }
    take(.self: &Self, .storage: $&Allocation, .slot: $&Tracked) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, storage)
        empties(storage)
    }
)

Tracked: Type = (.drops: $&Int32)

Tracked deinit(.self: $&Tracked) -> () := { self&.drops&= self&.drops&+ 1 }

Slots: Type = ()

Slots implements SlotProtocol

put(.self: &Slots, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked) -> () := {
    trusted_opaque_move_in#(Tracked, Allocation)(storage, slot, ~value)
}

take(.self: &Slots, .storage: $&Allocation, .slot: $&Tracked) -> (.value: Tracked) := {
    value = trusted_opaque_move_out#(Tracked, Allocation)(storage, slot)
    trusted_opaque_mark_empty(storage)
}

forward_put(
        .slots   : &Virtual#(SlotProtocol),
        .storage : $&Allocation,
        .slot    : $&Tracked,
        .value   : Tracked
    ) -> () := {
    put(slots, storage, slot, ~value)
}

forward_take(
        .slots   : &Virtual#(SlotProtocol),
        .storage : $&Allocation,
        .slot    : $&Tracked
    ) -> (
        .value : Tracked
    ) := {
    value = take(slots, storage, slot)
}

make_storage(.allocator: $&GeneralPurposeAllocator, .drops: $&Int32) -> (.result: Allocation) := {
    implementation ::= Slots()
    slots ::= to_virtual#(SlotProtocol)(&implementation)
    storage ::= unwrap_or_abort(allocate#(Tracked)(allocator))
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&storage, 0).reference
    ).reference

    forward_put(&slots, $&storage, slot, Tracked(drops))
    result = ~storage
}

escape(.allocator: $&GeneralPurposeAllocator) -> (.result: Tracked) := {
    drops :: Int32 = 0
    storage ::= make_storage(allocator, $&drops)
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&storage, 0).reference
    ).reference
    implementation ::= Slots()
    slots ::= to_virtual#(SlotProtocol)(&implementation)

    result = forward_take(&slots, $&storage, slot)
    deinit($&storage)
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    result ::= escape(allocator)
}
