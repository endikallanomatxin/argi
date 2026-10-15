unsafe_allocation := import("../../_support/unsafe_allocation")

SlotProtocol#(.Participant: Type): Contract = (
    domain contents

    .put: (.self: $&Participant, .value: Allocation) -> () where retains(self.contents, value)
    .take: (.self: $&Participant) -> (.value: Allocation) where {
        owns(value)
        from_storage(value, self.contents)
        empties(self.contents)
    }
)

Slot: Type = (.storage: Allocation)
implement SlotProtocol#(Slot) (.put = _impl_put_Slot, .take = _impl_take_Slot) where { contents(self.storage) }

_impl_put_Slot := (.self: $&Slot, .value: Allocation) -> ()  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Allocation)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference).reference
    trusted_opaque_move_in#(Allocation, Allocation)($&self&.storage, slot, ~value)
}

_impl_take_Slot := (.self: $&Slot) -> (.value: Allocation)  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Allocation)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference).reference
    value = trusted_opaque_move_out#(Allocation, Allocation)($&self&.storage, slot)
    trusted_opaque_mark_empty($&self&.storage)
}

forward_put(.slot: $&Virtual#(SlotProtocol), .value: Allocation) -> () := {
    put(slot, ~value)
}

forward_take(.slot: $&Virtual#(SlotProtocol)) -> (.value: Allocation) := {
    value = take(slot)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate#(Allocation)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)
    payload ::= unwrap_or_abort(allocate#(UInt8)(allocator))
    unsafe_allocation.trusted_allocation_byte_rw($&payload, 0).reference& = 42

    old_byte ::= unsafe_allocation.trusted_allocation_byte_ro(&payload, 0).reference
    forward_put($&slot, ~payload)
    extracted ::= forward_take($&slot)
    deinit($&implementation.storage)
    byte ::= unsafe_allocation.trusted_allocation_byte_ro(&extracted, 0).reference
    if old_byte& != byte& { status_code = 1 }
}
