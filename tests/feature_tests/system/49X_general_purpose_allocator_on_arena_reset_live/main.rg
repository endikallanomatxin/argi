unsafe_allocation := import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32 = 0) := {
    arena :: ArenaAllocator
    unwrap_or_abort(.value = init(.p = $&arena, .allocator = system.page_allocator))
    gpa ::= GeneralPurposeAllocator(.allocator = $&arena)
    allocation ::= unwrap_or_abort(.value = allocate(.self = $&gpa, .size = 32, .alignment = 8))
    reset(.self = $&arena)
    byte ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
    byte& = 1
    deinit(.self = $&allocation)
    deinit(.self = $&arena)
}
