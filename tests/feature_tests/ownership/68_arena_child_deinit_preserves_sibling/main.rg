main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 32)
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
                    second.data& = 23

                    if second.data& == 23 {
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
