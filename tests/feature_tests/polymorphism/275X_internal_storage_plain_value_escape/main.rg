unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked := (.drops: $&Int32)

SlotProtocol#(.Participant: Type): Contract = (
    domain contents

    .put  : (.self: $&Participant, .value: Tracked) -> () where retains(self.contents, value)
    .take : (.self: $&Participant) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, self.contents)
        empties(self.contents)
    }
)

Slot := (.storage: Allocation)

implement SlotProtocol#(Slot) (.put = _impl_put_Slot, .take = _impl_take_Slot) where {
    contents(self.storage)
}

_impl_put_Slot := (.self: $&Slot, .value: Tracked) -> () {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

_impl_take_Slot := (.self: $&Slot) -> (.value: Tracked) {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.storage, slot)
    trusted_opaque_mark_empty($&self&.storage)
}

forward_put := (.slot: $&Virtual#(SlotProtocol), .value: Tracked) -> () {
    put(slot, ~value)
}

forward_take := (.slot: $&Virtual#(SlotProtocol)) -> (.value: Tracked) {
    value = take(slot)
}

extract := (.allocator: $&GeneralPurposeAllocator, .drops: $&Int32) -> (.result: Tracked) {

    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)
    forward_put($&slot, Tracked(drops))
    result = forward_take($&slot)
    deinit($&implementation.storage)
}

escape := (.allocator: $&GeneralPurposeAllocator) -> (.result: Tracked) {

    drops :: Int32 = 0
    result = extract(allocator, $&drops)
}

main := (.system: System) -> () {

    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    value ::= escape(allocator)
}
