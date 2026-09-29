main(.system: System) -> (.status_code: Int32 = 0) := {
    arena :: ArenaAllocator
    unwrap_or_abort(.value = init(.p = $&arena, .allocator = system.page_allocator, .block_size = 16384))
    gpa ::= GeneralPurposeAllocator(.allocator = $&arena)

    small ::= unwrap_or_abort(.value = allocate(.self = $&gpa, .size = 32, .alignment = 16))
    large ::= unwrap_or_abort(.value = allocate(.self = $&gpa, .size = 4097, .alignment = 8192))
    if small.data.address % 16 != 0 or large.data.address % 8192 != 0 {
        status_code = 1
    }
    deinit(.self = $&small)
    deinit(.self = $&large)
    if has_live_allocations(.self = &gpa).has_live { status_code = 2 }
    reset(.self = $&arena)
    gpa_after_reset ::= GeneralPurposeAllocator(.allocator = $&arena)
    reused ::= unwrap_or_abort(.value = allocate(.self = $&gpa_after_reset, .size = 24, .alignment = 8))
    deinit(.self = $&reused)
    if has_live_allocations(.self = &gpa_after_reset).has_live { status_code = 3 }
    deinit(.self = $&arena)
}
