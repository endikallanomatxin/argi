unsafe_allocation := #import("../../_support/unsafe_allocation")
inner(.p: $&UInt8) -> (.result: UInt8) := {
    result = p&
}

outer(.p: $&UInt8) -> (.result: UInt8) := {
    result = inner(.p = p).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            pointer ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
            deinit(.self = $&allocation)
            observed ::= outer(.p = pointer).result
            if observed == 0 { status_code = 0 } else { status_code = 2 }
        }
    }
}
