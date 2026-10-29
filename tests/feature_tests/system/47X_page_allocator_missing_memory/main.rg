main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= PageAllocator()
    status_code = 0
}
