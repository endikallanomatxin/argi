main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    arena :: ArenaAllocator
    arena = unwrap_or_abort(.value = ArenaAllocator(.allocator = system.page_allocator))
    gpa ::= GeneralPurposeAllocator(.allocator = $&arena)
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = $&gpa, .size = 8192, .alignment = 4096)
    )
    reset(.self = $&arena)
    deinit(.self = $&allocation)
    deinit(.self = $&arena)
}
