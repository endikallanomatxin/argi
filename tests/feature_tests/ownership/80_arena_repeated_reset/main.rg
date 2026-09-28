unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    assume metadata_allocator ::= system.allocator

    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .metadata_allocator = system.allocator, .block_size = 16)
    if is(.value = initialized, .variant = ..error) {
        status_code = 1
        return
    }

    first_result ::= allocate(.self = $&arena, .size = 8)
    match first_result {
        ..error _ {
            deinit(.self = $&arena)
            status_code = 2
            return
        }
        ..ok ~ first_payload {
            first ::= ~first_payload
            byte_pointer_21 ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&first, .offset = 0).reference
            byte_pointer_21& = 1
            deinit(.self = $&first)
            reset(.self = $&arena)
        }
    }

    second_result ::= allocate(.self = $&arena, .size = 8)
    match second_result {
        ..error _ {
            deinit(.self = $&arena)
            status_code = 3
            return
        }
        ..ok ~ second_payload {
            second ::= ~second_payload
            byte_pointer_36 ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&second, .offset = 0).reference
            byte_pointer_36& = 2
            deinit(.self = $&second)
            reset(.self = $&arena)
        }
    }
    deinit(.self = $&arena)
    status_code = 0
}
