main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    storage ::= unwrap_or_abort(
        .value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi)
    )
    storage._size = 1000000
}
