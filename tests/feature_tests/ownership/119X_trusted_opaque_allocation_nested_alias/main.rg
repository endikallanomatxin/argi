unsafe_allocation := #import("../../_support/unsafe_allocation")
inner#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_move#(.t: t)(.destination = slot, .source = ~value)
}

outer#(.t: Type)(.slot: $&t, .value: t) -> () := {
    inner#(.t: t)(.slot = slot, .value = ~value)
}

main(.system: System) -> (.status_code: Int32) := {
    source_result ::= allocate(.self = system.page_allocator, .size = 1)
    slot_result ::= allocate(.self = system.page_allocator, .size = size_of(.type = Allocation))

    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            alias ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_allocation ::= ~slot_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slot_allocation, .offset = 0).reference).reference
                    outer#(.t: Allocation)(.slot = slot, .value = ~allocation)
                    alias& = 0
                    status_code = 0
                }
            }
        }
    }
}
