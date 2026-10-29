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
    .take : (.self: $&Participant, .present: Bool) -> (.value: ?Tracked) where {
        on value ..some {
            owns(value)
            from_storage(value, self.contents)
            empties(self.contents)
        }
        on value ..none {}
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

_impl_take_Slot := (.self: $&Slot, .present: Bool) -> (.value: ?Tracked) {
    if present {
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
        ).reference
        value = ..some(
            .value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.storage, slot)
        )
        trusted_opaque_mark_empty($&self&.storage)
        return
    } else {
        value = ..none
    }
}

forward_take := (.slot: $&Virtual#(SlotProtocol), .present: Bool) -> (.value: ?Tracked) {
    value = take(slot, present)
}

static_take := #(.SlotType: Type: SlotProtocol#(SlotType)) (.slot: $&SlotType, .present: Bool) -> (
    .value : ?Tracked
) {
    value = take(slot, present)
}

extract := (.allocator: $&GeneralPurposeAllocator, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .value : Tracked
) {
    assume error_tracer
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)
    drops :: Int32 = 0

    put($&slot, Tracked($&drops))
    result ::= forward_take($&slot, true)
    match result {
        ..some ~payload { value = ~payload.value }
        ..none { abort }
    }
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    _ ::= extract(allocator)
}
