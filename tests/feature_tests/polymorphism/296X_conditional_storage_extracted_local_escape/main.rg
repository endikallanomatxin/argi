unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        self&.drops&= self&.drops&+ 1
    }
)

SlotProtocol: Abstract = (
    domain contents

    put(.self: $&Self, .value: Tracked) -> () where retains(self.contents, value)
    take(.self: $&Self, .present: Bool) -> (.value: ?Tracked) where {
        on value ..some {
            owns(value)
            from_storage(value, self.contents)
            empties(self.contents)
        }
        on value ..none {}
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

take(.self: $&Slot, .present: Bool) -> (.value: ?Tracked) := {
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

forward_take(.slot: $&Virtual#(SlotProtocol), .present: Bool) -> (.value: ?Tracked) := {
    value = take(slot, present)
}

static_take(.slot: $&SlotProtocol, .present: Bool) -> (.value: ?Tracked) := {
    value = take(slot, present)
}

extract(.allocator: $&GeneralPurposeAllocator) -> (.value: Tracked) := {
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

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    _ ::= extract(allocator)
}
