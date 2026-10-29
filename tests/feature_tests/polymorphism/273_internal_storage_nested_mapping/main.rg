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

Inner := (.storage: Allocation)

Slot := (.inner: Inner)

implement SlotProtocol#(Slot) (.put = _impl_put_Slot, .take = _impl_take_Slot) where {
    contents(self.inner.storage)
}

_impl_put_Slot := (.self: $&Slot, .value: Tracked) -> () {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.inner.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.inner.storage, slot, ~value)
}

_impl_take_Slot := (.self: $&Slot) -> (.value: Tracked) {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.inner.storage, 0).reference
    ).reference
    value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.inner.storage, slot)
    trusted_opaque_mark_empty($&self&.inner.storage)
}

forward_put := (.slot: $&Virtual#(SlotProtocol), .value: Tracked) -> () {
    put(slot, ~value)
}

forward_take := (.slot: $&Virtual#(SlotProtocol)) -> (.value: Tracked) {
    value = take(slot)
}

static_put := #(.SlotType: Type: SlotProtocol#(SlotType)) (.slot: $&SlotType, .value: Tracked) -> (
) { put(slot, ~value) }

static_take := #(.SlotType: Type: SlotProtocol#(SlotType)) (.slot: $&SlotType) -> (
    .value : Tracked
) { value = take(slot) }

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0

    {
        implementation ::= Slot(Inner(unwrap_or_abort(allocate#(Tracked)(allocator))))
        slot ::= to_virtual#(SlotProtocol)($&implementation)
        forward_put($&slot, Tracked($&drops))
        extracted ::= forward_take($&slot)
        deinit($&implementation.inner.storage)
        if extracted.drops&!= 0 { status_code = 1 }
    }

    if drops != 1 { status_code = 2 }

    {
        implementation ::= Slot(Inner(unwrap_or_abort(allocate#(Tracked)(allocator))))
        static_put($&implementation, Tracked($&drops))
        extracted ::= static_take($&implementation)
        deinit($&implementation.inner.storage)
        if extracted.drops&!= 1 { status_code = 3 }
    }

    if drops != 2 { status_code = 4 }
}
