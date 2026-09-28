unsafe_allocation := #import("../../_support/unsafe_allocation")
identity(.p: $&UInt8) -> (.result: $&UInt8) := {
    result = p
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            pointer ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
            deinit(.self = $&allocation)
            stale_copy ::= identity(.p = pointer).result
            status_code = 0
        }
    }
}
