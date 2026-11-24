main := (.system: System) -> () {
    arena ::= unwrap_or_abort(ArenaAllocator(.allocator = system.page_allocator))
    allocation ::= unwrap_or_abort(allocate_bytes(.self = $&arena, .size = 8))
    reset(.self = $&arena)
    deinit(.self = $&allocation)
}
