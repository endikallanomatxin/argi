main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    ring ::= unwrap_or_abort(
        .value = RingBuffer#(.t: Int32)(.capacity = 1, .allocator = system.page_allocator)
    )
    ring._head = 1
    deinit(.self = $&ring)
}
