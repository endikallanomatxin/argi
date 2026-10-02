main(.system: System) -> (.status_code: Int32) := {
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    first ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
    match first {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first_allocation ::= ~first_payload
            first_data ::= first_allocation.data
            second ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
            match second {
                ..error _ { status_code = 1 }
                ..ok ~ second_payload {
                    second_allocation ::= ~second_payload
                    deinit(.self = $&first_allocation)
                    deallocate(.self = $&allocator, .data = first_data, .size = 8, .alignment = 8)
                    status_code = 0
                }
            }
        }
    }
}
