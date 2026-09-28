unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    assume metadata_allocator ::= system.allocator

    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .metadata_allocator = system.allocator, .block_size = 0)
    if is(.value = initialized, .variant = ..error) {
        status_code = 1
        return
    }

    result ::= allocate(.self = $&arena, .size = 0)
    match result {
        ..error _ {
            deinit(.self = $&arena)
            status_code = 2
        }
        ..ok ~ payload {
            child ::= ~payload
            if child.size != 0 {
                status_code = 3
                return
            }
            byte_pointer_24 ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&child, .offset = 0).reference
            byte_pointer_24& = 7
            if unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&child, .offset = 0).reference& != 7 {
                status_code = 4
                return
            }
            deinit(.self = $&child)
            deinit(.self = $&arena)
            status_code = 0
        }
    }
}
