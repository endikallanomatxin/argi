borrow := (.ring: &RingBuffer#(.t: Int32), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .reference : &Int32
) {
    assume error_tracer
    reference = unwrap_or_abort(.value = get_reference(.self = ring, .index = 0))
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    ring ::= unwrap_or_abort(
        .value = RingBuffer#(.t: Int32)(.capacity = 2, .allocator = system.page_allocator)
    )
    unwrap_or_abort(
        .value = push(.self = $&ring, .value = 7, .allocator = system.page_allocator)
    )
    borrowed ::= borrow(.ring = &ring).reference
    unwrap_or_abort(
        .value = push(.self = $&ring, .value = 8, .allocator = system.page_allocator)
    )
    observed ::= borrowed&
    deinit(.self = $&ring)
}
