main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)

    first ::= allocate(.self = $&arena, .size = 8)
    second ::= allocate(.self = $&arena, .size = 8)

    if cast#(.to: UIntNative)(.value = first.data) == 0 {
        status_code = 10
        return
    }

    if cast#(.to: UIntNative)(.value = second.data) == 0 {
        status_code = 11
        return
    }

    if arena.blocks.length != 1 {
        status_code = 12
        return
    }

    deinit(.self = $&first)
    second.data& = 9
    deinit(.self = $&second)

    reset(.self = $&arena)

    if arena.blocks.length != 0 {
        status_code = 13
        return
    }

    third ::= allocate(.self = $&arena, .size = 64)

    if cast#(.to: UIntNative)(.value = third.data) == 0 {
        status_code = 14
        return
    }

    deinit(.self = $&third)
    deinit(.self = $&arena)

    status_code = 0
}
