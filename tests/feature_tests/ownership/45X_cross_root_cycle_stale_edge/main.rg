unsafe_allocation := #import("../../_support/unsafe_allocation")
B : Type = (.value: UInt8, .to_a: $&UInt8)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    ref_a ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
    b :: B = (.value = 5, .to_a = ref_a)

    deinit(.self = $&allocation)
    if b.to_a& == 0 {
        status_code = 0
    }
    }
    }
}
