unsafe_allocation := import ("../../_support/unsafe_allocation")

SlotProtocol<.Value: Type>: Contract = (
    domain contents

    .put  : (.self: $&Value, .value: Allocation) -> () where retains(self.contents, value)
    .take : (.self: $&Value) -> (.value: Allocation) where {
        owns(value)
        from_storage(value, self.contents)
        empties(self.contents)
    }
)

Slot := (.storage: Allocation)

implement SlotProtocol<Slot> (
    .put  = _slot_put
    .take = _slot_take
) where { contents(self.storage) }

_slot_put := (.self: $&Slot, .value: Allocation) -> () {
    slot ::= trusted_mutable_reinterpret_reference<UInt8, Allocation>(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in<Allocation, Allocation>($&self&.storage, slot, ~value)
}

_slot_take := (.self: $&Slot) -> (.value: Allocation) {
    slot ::= trusted_mutable_reinterpret_reference<UInt8, Allocation>(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    value = trusted_opaque_move_out<Allocation, Allocation>($&self&.storage, slot)
    trusted_opaque_mark_empty($&self&.storage)
}

forward_put := (.slot: $&Virtual<SlotProtocol>, .value: Allocation) -> () {
    put(slot, ~value)
}

forward_take := (.slot: $&Virtual<SlotProtocol>) -> (.value: Allocation) {
    value = take(slot)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate<Allocation>(allocator)))
    slot ::= to_virtual<SlotProtocol>($&implementation)
    payload ::= unwrap_or_abort(allocate<UInt8>(allocator))
    unsafe_allocation.trusted_allocation_byte_rw($&payload, 0).reference&= 42

    forward_put($&slot, ~payload)
    extracted ::= forward_take($&slot)
    deinit($&implementation.storage)
    byte ::= unsafe_allocation.trusted_allocation_byte_ro(&extracted, 0).reference
    if byte&!= 42 { status_code = 1 }
}
