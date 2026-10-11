unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

NestedResult: Type = (..some ?Tracked, ..none)

Tracked deinit(.self: $&Tracked) -> () := { self&.drops&= self&.drops&+ 1 }

SlotProtocol: Abstract = (
    domain contents

    put(.self: $&Self, .value: Tracked) -> () where retains(self.contents, value)
    take(.self: $&Self, .present: Bool) -> (.value: NestedResult) where {
        empties(self.contents)
        on value ..some {
            on value ..some {
                owns(value)
                from_storage(value, self.contents)
            }
            on value ..none {}
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

take(.self: $&Slot, .present: Bool) -> (.value: NestedResult) := {
    if present {
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
        ).reference
        value = ..some ..some(
            .value = trusted_opaque_move_out#(Tracked, Allocation)($&self&.storage, slot)
        )
    } else {
        value = ..none
    }

    trusted_opaque_mark_empty($&self&.storage)
}

forward_take(.slot: $&Virtual#(SlotProtocol), .present: Bool) -> (.value: NestedResult) := {
    value = take(slot, present)
}

static_take(.slot: $&SlotProtocol, .present: Bool) -> (.value: NestedResult) := {
    value = take(slot, present)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    drops :: Int32 = 0

    {
        implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))
        slot ::= to_virtual#(SlotProtocol)($&implementation)
        put($&slot, Tracked($&drops))
        extracted ::= forward_take($&slot, true)
        deinit($&implementation.storage)

        match extracted {
            ..some ~outer {
                match ~outer {
                    ..some ~inner { if inner.value.drops&!= 0 { status_code = 1 } }
                    ..none { status_code = 2 }
                }
            }
            ..none { status_code = 3 }
        }
    }

    if drops != 1 { status_code = 4 }
}
