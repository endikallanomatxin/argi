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

forward_drain(.slot: $&Virtual#(SlotProtocol), .empty: Bool) -> (.result: ?Int32) := {
    saved ::= drain(slot, empty)
    result = saved
}

static_drain#(.SlotType: Type: SlotProtocol#(SlotType))(.slot: $&SlotType, .empty: Bool) -> (.result: ?Int32) := {
    result = drain(slot, empty)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)

    {
        drops :: Int32 = 0
        put($&slot, Tracked($&drops))
        result ::= forward_drain($&slot, true)
        match result {
            ..some payload { if payload.value != 42 { status_code = 1 } }
            ..none {
                status_code = 2
                return
            }
        }

        if drops != 1 { status_code = 3 }
    }

    _ ::= forward_drain($&slot, false)

    {
        drops :: Int32 = 0
        put($&implementation, Tracked($&drops))
        result ::= static_drain($&implementation, true)
        match result {
            ..some _ {}
            ..none {
                status_code = 4
                return
            }
        }

        if drops != 1 { status_code = 5 }
    }

    deinit($&implementation.storage)
}
