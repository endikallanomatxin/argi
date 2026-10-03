main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    allocation ::= unwrap_or_abort(.value = allocate(.self = $&allocator, .size = 32, .alignment = 8))
    allocation.data.address = 1
    allocation.size = 0
    allocation.alignment = 0
    -- Physical cleanup uses the original acquisition, not the edited receipt.
    deinit(.self = $&allocation)
}
