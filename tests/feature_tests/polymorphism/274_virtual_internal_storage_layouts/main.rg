unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked := (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

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

OtherSlot := (.padding: Int32, .storage: Allocation)

implement SlotProtocol#(OtherSlot) (.put = _impl_put_OtherSlot, .take = _impl_take_OtherSlot) where {
    contents(self.storage)
}

_impl_put_OtherSlot := (.self: $&OtherSlot, .value: Tracked) -> () {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

_impl_take_OtherSlot := (.self: $&OtherSlot) -> (.value: Tracked) {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.storage, slot)
    trusted_opaque_mark_empty($&self&.storage)
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0

    {
        implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
        slot ::= to_virtual#(SlotProtocol)($&implementation)
        forward_put($&slot, Tracked($&drops))
        extracted ::= forward_take($&slot)
        deinit($&implementation.storage)
        if extracted.drops&!= 0 { status_code = 1 }
    }

    if drops != 1 { status_code = 2 }

    {
        other ::= OtherSlot(13, unwrap_or_abort(allocate#(Tracked)(allocator)))
        other_slot ::= to_virtual#(SlotProtocol)($&other)
        forward_put($&other_slot, Tracked($&drops))
        extracted ::= forward_take($&other_slot)
        deinit($&other.storage)
        if extracted.drops&!= 1 { status_code = 3 }
    }

    if drops != 2 { status_code = 4 }
}
