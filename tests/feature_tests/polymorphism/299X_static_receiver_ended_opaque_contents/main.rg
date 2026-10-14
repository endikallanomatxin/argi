unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

SlotProtocol#(.Participant: Type): Contract = (
    domain contents

    .put: (.self: $&Participant, .value: Tracked) -> () where retains(self.contents, value)
    .drain: (.self: $&Participant, .empty: Bool) -> (.result: ?Int32) where {
        on result ..some { empties(self.contents) }
        on result ..none {}
    }
)

Slot: Type = (.storage: Allocation)

implement SlotProtocol#(Slot) (.put = _impl_put_Slot, .drain = _impl_drain_Slot) where { contents(self.storage) }

_impl_put_Slot := (.self: $&Slot, .value: Tracked) -> ()  {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

_impl_drain_Slot := (.self: $&Slot, .empty: Bool) -> (.result: ?Int32)  {
    if empty {
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
        ).reference
        trusted_opaque_drop#(Tracked)(slot)
        trusted_opaque_mark_empty($&self&.storage)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

static_drain(.slot: $&SlotProtocol, .empty: Bool) -> (.result: ?Int32) := {
    result = drain(slot, empty)
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
    receiver ::= $&implementation

    {
        drops :: Int32 = 0
        put($&implementation, Tracked($&drops))
    }

    _ ::= static_drain(receiver, true)
    deinit($&implementation.storage)
}
