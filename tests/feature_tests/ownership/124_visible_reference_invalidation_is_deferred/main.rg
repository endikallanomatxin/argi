unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            visible ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference

            -- Merely keeping a precise reference alive does not prevent the
            -- operation that ends its root. The checker rejects only a later
            -- use of `visible` (covered by the companion negative test).
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
