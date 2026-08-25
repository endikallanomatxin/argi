main(.system: System) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    data ::= allocate(.self = $&arena, .size = 1)
    alias ::= data
    reset(.self = $&arena)
    if alias& == 0 {
        status_code = 0
    }
}
