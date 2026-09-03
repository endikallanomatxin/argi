main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 32)
    if is(.value = initialized, .variant = ..error) {
        status_code = 18
        return
    }

    first_result ::= allocate(.self = $&arena, .size = 8)
    match first_result {
    ..error _ {
    deinit(.self = $&arena)
    status_code = 15
    }
    ..ok ~ first_payload {
    first ::= ~first_payload
    second_result ::= allocate(.self = $&arena, .size = 8)
    match second_result {
    ..error _ {
    deinit(.self = $&first)
    deinit(.self = $&arena)
    status_code = 16
    }
    ..ok ~ second_payload {
    second ::= ~second_payload

    if cast#(.to: UIntNative)(.value = first.data) == 0 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 10
        return
    }

    if cast#(.to: UIntNative)(.value = second.data) == 0 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 11
        return
    }

    if arena.blocks.length != 1 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 12
        return
    }

    deinit(.self = $&first)
    second.data& = 9
    deinit(.self = $&second)

    reset(.self = $&arena)

    if arena.blocks.length != 0 {
        deinit(.self = $&arena)
        status_code = 13
        return
    }

    third_result ::= allocate(.self = $&arena, .size = 64)
    match third_result {
    ..error _ {
    deinit(.self = $&arena)
    status_code = 17
    }
    ..ok ~ third_payload {
    third ::= ~third_payload

    if cast#(.to: UIntNative)(.value = third.data) == 0 {
        deinit(.self = $&third)
        deinit(.self = $&arena)
        status_code = 14
        return
    }

    deinit(.self = $&third)
    deinit(.self = $&arena)
    status_code = 0
    }
    }
    }
    }
    }
    }
}
