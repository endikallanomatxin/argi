unsafe_allocation := import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = $&allocator_storage, .block_size = 32)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ {
        status_code = 2
        return
    }
    }
    result ::= allocate(.self = $&arena, .size = 8)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            child ::= ~payload
            reset(.self = $&arena)
            byte_pointer_14 ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&child, .offset = 0).reference
            byte_pointer_14& = 1
        }
    }

    status_code = 0
}
