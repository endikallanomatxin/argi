unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

Pair: Type = (.first: Tracked, .second: Tracked)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

Slots: Type = ()

SlotProtocol: Abstract = (
    take_pair(
        .self        : &Self,
        .first       : $&Allocation,
        .first_slot  : $&Tracked,
        .second      : $&Allocation,
        .second_slot : $&Tracked
    ) -> (.value: Pair) where {
        owns(value)
        from_storage(value, first, second, first)
        empties(first)
        empties(second)
    }
)

Slots implements SlotProtocol

take_pair(
        .self        : &Slots,
        .first       : $&Allocation,
        .first_slot  : $&Tracked,
        .second      : $&Allocation,
        .second_slot : $&Tracked
    ) -> (
        .value : Pair
    ) := {
    first_value ::= trusted_opaque_move_out#(Tracked, Allocation)(first, first_slot)
    second_value ::= trusted_opaque_move_out#(Tracked, Allocation)(second, second_slot)
    trusted_opaque_mark_empty(first)
    trusted_opaque_mark_empty(second)

    value = Pair(~first_value, ~second_value)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0

    {
        first ::= unwrap_or_abort(allocate#(Tracked)(allocator))
        second ::= unwrap_or_abort(allocate#(Tracked)(allocator))
        first_slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&first, 0).reference
        ).reference
        second_slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&second, 0).reference
        ).reference
        trusted_opaque_move_in#(Tracked, Allocation)($&first, first_slot, Tracked($&drops))
        trusted_opaque_move_in#(Tracked, Allocation)($&second, second_slot, Tracked($&drops))
        implementation ::= Slots()
        slots ::= to_virtual#(SlotProtocol)(&implementation)

        pair ::= take_pair(&slots, $&first, first_slot, $&second, second_slot)
        deinit($&first)
        deinit($&second)
        if pair.first.drops&!= 0 { status_code = 1 }
        if pair.second.drops&!= 0 { status_code = 2 }
    }

    if drops != 2 { status_code = 3 }
}
