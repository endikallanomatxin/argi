main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    result ::= allocate_bytes(.self = $&allocator, .size = 16, .alignment = 8)
    match result {
        ..error _ { abort }
        ..ok ~memory { status_code = 42 }
    }
}
