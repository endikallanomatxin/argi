unsafe_allocation := import ("../../_support/unsafe_allocation")

SlotProtocol#(.Participant: Type): Contract = (
    .put : (.self: &Participant, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked) -> () where {
        retains(storage, value)
    }
    .take : (.self: &Participant, .storage: $&Allocation, .slot: $&Tracked) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, storage)
        empties(storage)
    }
)

Tracked := (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

Slots: Type = ()

implement SlotProtocol#(Slots) (.put = _impl_put_Slots, .take = _impl_take_Slots)

_impl_put_Slots := (.self: &Slots, .storage: $&Allocation, .slot: $&Tracked, .value: Tracked) -> (
) {
    trusted_opaque_move_in#(Tracked, Allocation)(storage, slot, ~value)
}

_impl_take_Slots := (.self: &Slots, .storage: $&Allocation, .slot: $&Tracked) -> (
    .value : Tracked
) {
    value = trusted_opaque_move_out#(Tracked, Allocation)(storage, slot)
    trusted_opaque_mark_empty(storage)
}

forward_put := (
    .slots: &Virtual#(SlotProtocol), .storage: $&Allocation, .slot: $&Tracked, .value: Tracked
) -> () {
    put(slots, storage, slot, ~value)
}

forward_take := (.slots: &Virtual#(SlotProtocol), .storage: $&Allocation, .slot: $&Tracked) -> (
    .value : Tracked
) {
    value = take(slots, storage, slot)
}

escape := (.system: System) -> (.result: Tracked) {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0
    implementation ::= Slots()
    slots ::= to_virtual#(SlotProtocol)(&implementation)

    {
        storage ::= unwrap_or_abort(allocate#(Tracked)(allocator))
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&storage, 0).reference
        ).reference
        forward_put(&slots, $&storage, slot, Tracked($&drops))
        result = forward_take(&slots, $&storage, slot)
        deinit($&storage)
    }

}

main := (.system: System) -> () { escape(system) }
