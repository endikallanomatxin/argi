unsafe_allocation := import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    blocker_result ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
    match blocker_result {
        ..error _ { status_code = 1 }
        ..ok ~ blocker_payload {
            blocker ::= ~blocker_payload
            first_result ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    first ::= ~first_payload
                    previous_address ::= first.data.address
                    borrowed ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&first, .offset = 0).reference
                    borrowed& = 17
                    deinit(.self = $&first)
                    replacement_result ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
                    match replacement_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ replacement_payload {
                            replacement ::= ~replacement_payload
                            if replacement.data.address != previous_address { status_code = 4
                                return }
                            -- Reusing an address must not revive the old root.
                            observed ::= borrowed&
                            if observed == 17 { status_code = 5 }
                        }
                    }
                }
            }
        }
    }
}
