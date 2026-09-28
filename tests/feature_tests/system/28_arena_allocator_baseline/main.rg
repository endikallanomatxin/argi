main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    assume backing_allocator ::= system.allocator

    arena :: ArenaAllocator
    initialized ::= init(.p = $&arena, .backing_allocator = system.allocator, .block_size = 64)
    if is(.value = initialized, .variant = ..error) {
        status_code = 18
        return
    }

    first_result ::= allocate(.self = $&arena, .size = 1)
    match first_result {
    ..error _ {
    deinit(.self = $&arena)
    status_code = 15
    }
    ..ok ~ first_payload {
    first ::= ~first_payload
    second_result ::= allocate(.self = $&arena, .size = 8, .alignment = 32)
    match second_result {
    ..error _ {
    deinit(.self = $&first)
    deinit(.self = $&arena)
    status_code = 16
    }
    ..ok ~ second_payload {
    second ::= ~second_payload

    if first.data.address == 0 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 10
        return
    }

    if second.data.address == 0 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 11
        return
    }

    if second.data.address % 32 != 0 or second.alignment != 32 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 19
        return
    }

    if length#(.t: ArenaBlock)(.self = &arena.blocks).count != 1 {
        deinit(.self = $&first)
        deinit(.self = $&second)
        deinit(.self = $&arena)
        status_code = 12
        return
    }

    deinit(.self = $&first)
    byte_pointer_55 ::= trusted_allocation_byte_rw(.allocation = $&second, .offset = 0).reference
    byte_pointer_55& = 9
    deinit(.self = $&second)

    reset(.self = $&arena)

    if length#(.t: ArenaBlock)(.self = &arena.blocks).count != 0 {
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

    if third.data.address == 0 {
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
