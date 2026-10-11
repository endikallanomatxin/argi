unsafe_allocation := import ("../../_support/unsafe_allocation")

Tracked: Type = (.drops: $&Int32)

Tracked deinit(.self: $&Tracked) -> () := { self&.drops&= self&.drops&+ 1 }

Slot: Type = (.storage: Allocation)

put(.self: $&Slot, .value: Tracked) -> () := {
    slot ::= trusted_mutable_reinterpret_reference#(UInt8, Tracked)(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in#(Tracked, Allocation)($&self&.storage, slot, ~value)
}

drain(.self: $&Slot, .empty: Bool) -> (.result: ?Int32) := {
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

main(.system: System) -> () := {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate#(Tracked)(allocator)))

    {
        drops :: Int32 = 0
        put($&implementation, Tracked($&drops))
    }

    _ ::= drain($&implementation, true)
    deinit($&implementation.storage)
}
