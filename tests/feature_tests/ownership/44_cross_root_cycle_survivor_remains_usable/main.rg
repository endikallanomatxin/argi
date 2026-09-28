unsafe_allocation := #import("../../_support/unsafe_allocation")
A : Type = (.value: UInt8, .to_b: $&UInt8)
B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    result_a ::= allocate(.self = $&allocator_storage, .size = 1)
    match result_a {
    ..error _ { status_code = 3 }
    ..ok ~ payload_a {
    allocation_a ::= ~payload_a
    result_b ::= allocate(.self = $&allocator_storage, .size = 1)
    match result_b {
    ..error _ { status_code = 4 }
    ..ok ~ payload_b {
    allocation_b ::= ~payload_b
    ref_a ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation_a, .offset = 0).reference
    ref_b ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation_b, .offset = 0).reference
    a :: A = (.value = 3, .to_b = ref_b)
    b :: B = (.value = 5, .to_a = ref_a)

    deinit(.self = $&allocation_a)
    status_code = 0
    if b.value != 5 {
        status_code = 1
    }
    if a.to_b& != 0 {
        status_code = 2
    }
    deinit(.self = $&allocation_b)
    }
    }
    }
    }
}
