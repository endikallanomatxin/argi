unsafe_allocation := import ("../../_support/unsafe_allocation")

CountReference := (.count: $&Int32)

Slot := (.storage: Allocation)

put := (.self: $&Slot, .value: CountReference) -> () {
    slot ::= trusted_mutable_reinterpret_reference<UInt8, CountReference>(
        unsafe_allocation.trusted_allocation_byte_rw($&self&.storage, 0).reference
    ).reference
    trusted_opaque_move_in<CountReference, Allocation>($&self&.storage, slot, ~value)
}

main := (.system: System) -> () {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    implementation ::= Slot(unwrap_or_abort(allocate<CountReference>(allocator)))

    {
        count :: Int32 = 0
        put($&implementation, CountReference($&count))
    }

    deinit($&implementation.storage)
}
