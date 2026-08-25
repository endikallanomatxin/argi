read(.value: &UInt8) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    first ::= allocate(.self = $&arena, .size = 1)
    second ::= allocate(.self = $&arena, .size = 1)
    read(.value = first)
    read(.value = second)
    reset(.self = $&arena)
    deinit(.self = $&arena)
    status_code = 0
}
