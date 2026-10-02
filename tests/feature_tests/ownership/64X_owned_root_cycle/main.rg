unsafe_allocation := import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    result_a ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Allocation))
    match result_a {
    ..error _ { status_code = 1 }
    ..ok ~ payload_a {
    a ::= ~payload_a
    result_b ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Allocation))
    match result_b {
    ..error _ { status_code = 2 }
    ..ok ~ payload_b {
    b ::= ~payload_b
    slot_a ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&a, .offset = 0).reference).reference
    slot_b ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&b, .offset = 0).reference).reference

    slot_a& = ~b
    slot_b& = ~a
    status_code = 0
    }
    }
    }
    }
}
