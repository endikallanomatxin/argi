unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked := (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

SlotProtocol#(.Participant: Type): Contract = (
    domain contents

    .put   : (.self: $&Participant, .value: Tracked) -> () where retains(self.contents, value)
    .drain : (.self: $&Participant, .empty: Bool) -> (.result: ?Int32) where {
        on result ..some { empties(self.contents) }
        on result ..none {}
    }
)

Slot := (.storage: Allocation)

implement SlotProtocol#(Slot) (.put = _impl_put_Slot, .drain = _impl_drain_Slot) where {
    contents(self.storage)
}

_impl_put_Slot := (.self: $&Slot, .value: Tracked) -> () {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

_impl_drain_Slot := (.self: $&Slot, .empty: Bool) -> (.result: ?Int32) {
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

static_drain := #(.SlotType: Type: SlotProtocol#(SlotType)) (.slot: $&SlotType, .empty: Bool) -> (
    .result : ?Int32
) {
    result = drain(slot, empty)
}

read_count := (.self: $&Slot) -> (.result: Int32) {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    result = slot&.drops&
}

main := (.system: System) -> () {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))

    {
        drops :: Int32 = 0
        put($&implementation, Tracked($&drops))
        if read_count($&implementation) != 0 { abort }
        _ ::= static_drain($&implementation, true)
        if drops != 1 { abort }
    }

    deinit($&implementation.storage)
}
