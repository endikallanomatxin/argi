unsafe_allocation := import("../../_support/unsafe_allocation")
Observer : Type = (.reference: $&UInt8)

Observer deinit(.self: $&Observer) -> () := {
    observed ::= self&.reference&
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            if 1 == 1 {
                observer ::= Observer(.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference)
                deinit(.self = $&allocation)
            }
            status_code = 0
        }
    }
}
