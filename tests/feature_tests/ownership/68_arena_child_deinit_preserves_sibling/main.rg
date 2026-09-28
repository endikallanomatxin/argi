unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    assume backing_allocator ::= $&allocator_storage

    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .allocator = $&allocator_storage, .block_size = 32)
    if is(.value = initialized, .variant = ..error) {
        status_code = 4
        return
    }
    first_result ::= allocate(.self = $&arena, .size = 8)
    match first_result {
        ..error _ {
            status_code = 2
            return
        }
        ..ok ~ first_payload {
            first ::= ~first_payload
            second_result ::= allocate(.self = $&arena, .size = 8)
            match second_result {
                ..error _ {
                    status_code = 3
                    return
                }
                ..ok ~ second_payload {
                    second ::= ~second_payload

                    deinit(.self = $&first)
                    byte_pointer_29 ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&second, .offset = 0).reference
                    byte_pointer_29& = 23

                    if unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&second, .offset = 0).reference& == 23 {
                        status_code = 0
                    } else {
                        status_code = 1
                    }

                    deinit(.self = $&second)
                }
            }
        }
    }
    deinit(.self = $&arena)
}
