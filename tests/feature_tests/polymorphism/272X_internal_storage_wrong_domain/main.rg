unsafe_allocation := import("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)
implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops& = self&.drops& + 1
    }
)

SlotProtocol#(.Participant: Type): Contract = (
    domain left
    domain right
    .put_left: (.self: $&Participant, .value: Tracked) -> () where retains(self.left, value)
    .take_left: (.self: $&Participant) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, self.left)
        empties(self.left)
    }
    .put_right: (.self: $&Participant, .value: Tracked) -> () where retains(self.right, value)
    .take_right: (.self: $&Participant) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, self.right)
        empties(self.right)
    }
)

Slot: Type = (.left: Allocation, .right: Allocation)
implement SlotProtocol#(Slot) (.put_left = _impl_put_left_Slot, .take_left = _impl_take_left_Slot, .put_right = _impl_put_right_Slot, .take_right = _impl_take_right_Slot) where {
    left(self.left)
    right(self.right)
}

_impl_put_left_Slot := (.self: $&Slot, .value: Tracked) -> ()  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.right, 0).reference).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.right, slot, ~value)
}

_impl_take_left_Slot := (.self: $&Slot) -> (.value: Tracked)  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.left, 0).reference).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.left, slot)
    trusted_opaque_mark_empty($&self&.left)
}

_impl_put_right_Slot := (.self: $&Slot, .value: Tracked) -> ()  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.right, 0).reference).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.right, slot, ~value)
}

_impl_take_right_Slot := (.self: $&Slot) -> (.value: Tracked)  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.right, 0).reference).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.right, slot)
    trusted_opaque_mark_empty($&self&.right)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    left_drops :: Int32 = 0
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)), unwrap_or_abort(allocate#(Tracked)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)
    put_left($&slot, Tracked($&left_drops))

    {
        right_drops :: Int32 = 0
        {
            put_right($&slot, Tracked($&right_drops))
            right ::= take_right($&slot)
            if right.drops& != 0 { status_code = 1 }
        }
        if right_drops != 1 { status_code = 2 }
    }

    {
        left ::= take_left($&slot)
        if left.drops& != 0 { status_code = 3 }
    }
    if left_drops != 1 { status_code = 4 }
}
