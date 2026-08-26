main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    first ::= allocate(.self = $&arena, .size = 8)
    second ::= allocate(.self = $&arena, .size = 8)

    deinit(.self = $&first)
    second.data& = 23

    if second.data& == 23 {
        status_code = 0
    } else {
        status_code = 1
    }

    deinit(.self = $&second)
    deinit(.self = $&arena)
}
