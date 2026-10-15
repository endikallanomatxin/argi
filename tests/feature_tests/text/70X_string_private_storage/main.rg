main(.system: System) -> () := {
    assume allocator ::= system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    text ::= unwrap_or_abort(.value = String())
    text._length = 100
}
