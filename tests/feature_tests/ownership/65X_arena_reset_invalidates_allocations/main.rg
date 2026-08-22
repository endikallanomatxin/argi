read(.value: &UInt8) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = system.allocator, .block_size = 32)
    pointer ::= allocate(.self = $&arena, .size = 1)
    reset(.self = $$&arena)
    read(.value = pointer)
    deinit(.self = $$&arena)
    status_code = 0
}
