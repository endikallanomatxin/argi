main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    queue ::= unwrap_or_abort(.value = Deque#(.t: Int32)())
    copy ::= queue
    length(.self = &copy)
}
