main(.system: System) -> (.status_code: Int32 = 0) := {
    arena :: ArenaAllocator
    arena = unwrap_or_abort(.value = ArenaAllocator(.allocator = system.page_allocator))
    gpa ::= GeneralPurposeAllocator(.allocator = $&arena)
    allocation ::= unwrap_or_abort(.value = allocate(.self = $&gpa, .size = 8192, .alignment = 4096))
    reset(.self = $&arena)
    deinit(.self = $&allocation)
    deinit(.self = $&arena)
}
