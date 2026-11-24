main := (.system: System) -> (.status_code: Int32) {

    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    first ::= allocate_bytes(.self = $&allocator, .size = 8, .alignment = 8)
    match first {
        ..error _ { status_code = 1 }
        ..ok ~first_payload {
            first_allocation ::= ~first_payload
            first_data ::= first_allocation.data
            second ::= allocate_bytes(.self = $&allocator, .size = 8, .alignment = 8)
            match second {
                ..error _ { status_code = 1 }
                ..ok ~second_payload {
                    second_allocation ::= ~second_payload
                    deinit(.self = $&first_allocation)
                    request ::= trusted_deallocation_request(.data = first_data, .size = 8, .alignment = 8, .ffi = system.ffi)
                    Deallocator#(
                    ).deallocate(
                        .self = $&allocator, .request = ~request
                    )
                    status_code = 0
                }
            }
        }
    }
}
