main(.system: System) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    old ::= allocate(.self = $&arena, .size = 1)
    reset(.self = $&arena)
    current ::= allocate(.self = $&arena, .size = 1)
    current& = 9
    if current& == 9 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&arena)
}
