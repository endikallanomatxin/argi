unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked := (.drops: $&Int32)

Pair := (.first: Tracked, .second: Tracked)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

Slots: Type = ()

SlotProtocol#(.Participant: Type): Contract = (
    .take_pair : (
        .self        : &Participant,
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

implement SlotProtocol#(Slots) (.take_pair = _impl_take_pair_Slots)

_impl_take_pair_Slots := (
    .self        : &Slots,
    .first       : $&Allocation,
    .first_slot  : $&Tracked,
    .second      : $&Allocation,
    .second_slot : $&Tracked
) -> (.value: Pair) {
    first_value ::= trusted_opaque_move_out#(Tracked, Allocation)(first, first_slot)
    second_value ::= trusted_opaque_move_out#(Tracked, Allocation)(second, second_slot)
    trusted_opaque_mark_empty(first)
    trusted_opaque_mark_empty(second)

    value = Pair(~first_value, ~second_value)
}

escape := (
    .allocator    : $&GeneralPurposeAllocator,
    .drops        : $&Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Pair) {
    assume error_tracer
    local_drops :: Int32 = 0
    first ::= unwrap_or_abort(allocate#(Tracked)(allocator))
    second ::= unwrap_or_abort(allocate#(Tracked)(allocator))
    first_slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&first, 0).reference
    ).reference
    second_slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&second, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&first, first_slot, Tracked(drops))
    trusted_opaque_move_in#(Tracked, Allocation)($&second, second_slot, Tracked($&local_drops))
    implementation ::= Slots()
    slots ::= to_virtual#(SlotProtocol)(&implementation)

    result = take_pair(&slots, $&first, first_slot, $&second, second_slot)
    deinit($&first)
    deinit($&second)
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0
    pair ::= escape(allocator, $&drops)
}
