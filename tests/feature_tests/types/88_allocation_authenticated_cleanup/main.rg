main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = $&allocator, .size = 32, .alignment = 8)
    )
    allocation.data.address = 1
    allocation.size = 0
    allocation.alignment = 0
    -- Physical cleanup uses the original acquisition, not the edited receipt.
    deinit(.self = $&allocation)
}
