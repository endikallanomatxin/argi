main(.system: System) -> () := {
    assume allocator ::= system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    text ::= unwrap_or_abort(.value = String(.length = 4))
    borrowed ::= as_view(&text)
    clear($&text)
    _ ::= bytes_get(.view = &borrowed, .index = 0)
}
