unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

SlotProtocol: Abstract = (
    domain left
    domain right
    put_left(.self: $&Self, .value: Tracked) -> () where retains(self.left, value)
    take_left(.self: $&Self) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, self.left)
        empties(self.left)
    }
    put_right(.self: $&Self, .value: Tracked) -> () where retains(self.right, value)
    take_right(.self: $&Self) -> (.value: Tracked) where {
        owns(value)
        from_storage(value, self.right)
        empties(self.right)
    }
)

Slot: Type = (.left: Allocation, .right: Allocation)

Slot implements SlotProtocol where {
    left(self.left)
    right(self.right)
}

put_left(.self: $&Slot, .value: Tracked) -> () := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.left, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.left, slot, ~value)
}

take_left(.self: $&Slot) -> (.value: Tracked) := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.left, 0).reference
    ).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.left, slot)
    trusted_opaque_mark_empty($&self&.left)
}

put_right(.self: $&Slot, .value: Tracked) -> () := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.right, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.right, slot, ~value)
}

take_right(.self: $&Slot) -> (.value: Tracked) := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.right, 0).reference
    ).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.right, slot)
    trusted_opaque_mark_empty($&self&.right)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    left_drops :: Int32 = 0
    implementation ::= Slot(
        unwrap_or_abort(allocate#(Tracked)(allocator))
        unwrap_or_abort(allocate#(Tracked)(allocator))
    )
    slot ::= to_virtual#(SlotProtocol)($&implementation)
    put_left($&slot, Tracked($&left_drops))

    {
        right_drops :: Int32 = 0
        {
            put_right($&slot, Tracked($&right_drops))
            right ::= take_right($&slot)
            if right.drops&!= 0 { status_code = 1 }
        }
        if right_drops != 1 { status_code = 2 }
    }

    {
        left ::= take_left($&slot)
        if left.drops&!= 0 { status_code = 3 }
    }
    if left_drops != 1 { status_code = 4 }
}
