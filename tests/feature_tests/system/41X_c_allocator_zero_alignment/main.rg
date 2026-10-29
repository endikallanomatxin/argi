main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator :: CAllocator = CAllocator(.ffi = system.ffi)
    allocated ::= allocate_bytes(.self = $&allocator, .size = 8, .alignment = 0)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
