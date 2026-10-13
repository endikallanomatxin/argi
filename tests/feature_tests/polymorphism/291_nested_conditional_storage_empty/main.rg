unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

NestedResult: Type = (..some ?Int32, ..none)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

SlotProtocol: Abstract = (
    domain contents

    put(.self: $&Self, .value: Tracked) -> () where retains(self.contents, value)
    drain(.self: $&Self, .empty: Bool) -> (.result: NestedResult) where {
        on result ..some {
            on result ..some { empties(self.contents) }
            on result ..none {}
        }
        on result ..none {}
    }
)

Slot: Type = (.storage: Allocation)

Slot implements SlotProtocol where { contents(self.storage) }

put(.self: $&Slot, .value: Tracked) -> () := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

drain(.self: $&Slot, .empty: Bool) -> (.result: NestedResult) := {
    if empty {
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
        ).reference
        trusted_opaque_drop#(Tracked)(slot)
        trusted_opaque_mark_empty($&self&.storage)
        result = ..some ..some(.value = 42)
        return
    }

    result = ..none
}

forward_drain(.slot: $&Virtual#(SlotProtocol), .empty: Bool) -> (.result: NestedResult) := {
    saved ::= drain(slot, empty)
    result = saved
}

static_drain(.slot: $&SlotProtocol, .empty: Bool) -> (.result: NestedResult) := {
    result = drain(slot, empty)
}

make_slot(.allocator: $&GeneralPurposeAllocator) -> (.value: Slot) := {
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
    slot ::= to_virtual#(SlotProtocol)($&implementation)

    {
        drops :: Int32 = 0
        put($&slot, Tracked($&drops))
        saved ::= forward_drain($&slot, true)
        result ::= saved
        match result {
            ..some payload {
                match payload {
                    ..some _ {}
                    ..none { abort }
                }
            }
            ..none { abort }
        }
    }

    value = ~implementation
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= make_slot(allocator)
    deinit($&implementation.storage)
}
