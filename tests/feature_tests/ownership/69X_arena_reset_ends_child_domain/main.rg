main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 32)
    if is(.value = initialized, .variant = ..error) {
        status_code = 2
        return
    }
    result ::= allocate(.self = $&arena, .size = 8)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            child ::= ~payload
            reset(.self = $&arena)
            child.data& = 1
        }
    }

    status_code = 0
}
