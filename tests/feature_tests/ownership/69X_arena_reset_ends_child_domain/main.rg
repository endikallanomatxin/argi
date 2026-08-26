main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    child ::= allocate(.self = $&arena, .size = 8)

    reset(.self = $&arena)
    child.data& = 1

    status_code = 0
}
