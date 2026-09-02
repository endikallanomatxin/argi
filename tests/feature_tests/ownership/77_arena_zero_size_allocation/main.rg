main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 0)
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
            child.data& = 7
            if child.data& != 7 {
                status_code = 4
                return
            }
            deinit(.self = $&child)
            deinit(.self = $&arena)
            status_code = 0
        }
    }
}
