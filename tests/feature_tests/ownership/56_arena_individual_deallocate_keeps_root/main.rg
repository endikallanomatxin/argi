main(.system: System) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    data ::= allocate(.self = $&arena, .size = 1)
    data& = 7
    alias ::= data
    deallocate(.self = $&arena, .data = data, .size = 1)
    if alias& == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&arena)
}
