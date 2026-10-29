main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
        .value = $&allocator
    )
    allocation ::= establish_allocation(
        .storage = ~123, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    deinit(.self = $&allocation)
}
