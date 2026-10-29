main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocation ::= unwrap_or_abort(
        .value = allocate_bytes(.self = system.page_allocator, .size = 32, .alignment = 8)
    )
    allocation._storage_size = 1000000
    deinit(.self = $&allocation)
}
