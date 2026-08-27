main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 16)
    if is(.value = initialized, .variant = ..error) {
        status_code = 1
        return
    }

    first_result ::= allocate(.self = $&arena, .size = 8)
    match first_result {
        ..error _ { status_code = 2 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            first.data& = 1
            reset(.self = $&arena)

            second_result ::= allocate(.self = $&arena, .size = 8)
            match second_result {
                ..error _ { status_code = 3 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    second.data& = 2
                    reset(.self = $&arena)
                    deinit(.self = $&second)
                }
            }
            deinit(.self = $&first)
        }
    }
    deinit(.self = $&arena)
    status_code = 0
}
