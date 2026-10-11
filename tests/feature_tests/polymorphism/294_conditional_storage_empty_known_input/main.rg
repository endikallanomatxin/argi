unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

Tracked deinit(.self: $&Tracked) -> () := { self&.drops&= self&.drops&+ 1 }

SlotProtocol: Abstract = (
    put(.self: &Self, .storage: $&Allocation, .value: Tracked) -> () where retains(storage, value)
    drain(.self: &Self, .storage: $&Allocation, .empty: Bool) -> (.result: ?Int32) where {
        on result ..some { empties(storage) }
        on result ..none {}
    }
)

Backend: Type = ()

Backend implements SlotProtocol

put(.self: &Backend, .storage: $&Allocation, .value: Tracked) -> () := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw(storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)(storage, slot, ~value)
}

drain(.self: &Backend, .storage: $&Allocation, .empty: Bool) -> (.result: ?Int32) := {
    if empty {
        slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
            unsafe_allocation.trusted_allocation_byte_rw(storage, 0).reference
        ).reference
        trusted_opaque_drop#(Tracked)(slot)
        trusted_opaque_mark_empty(storage)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

forward_drain(.backend: &Virtual#(SlotProtocol), .storage: $&Allocation) -> (.result: ?Int32) := {
    saved ::= drain(backend, storage, true)
    result = saved
}

make_storage(.allocator: $&GeneralPurposeAllocator) -> (.value: Allocation) := {
    storage ::= unwrap_or_abort(allocate#(Tracked)(allocator))
    backend ::= Backend()
    protocol ::= to_virtual#(SlotProtocol)(&backend)

    {
        drops :: Int32 = 0
        put(&protocol, $&storage, Tracked($&drops))
        result ::= forward_drain(&protocol, $&storage)
        match result {
            ..some _ {}
            ..none { abort }
        }
    }

    value = ~storage
}

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    storage ::= make_storage(allocator)
    deinit($&storage)
}
