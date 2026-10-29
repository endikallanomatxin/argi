main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator := system.page_allocator
    text ::= unwrap_or_abort(.value = string_from_bytes(.bytes = string_bytes(.text = "abc")))
    old ::= view(&text)
    unwrap_or_abort(.value = set_ascii($&text, .index = 0, .byte = 65))
    _ ::= bytes_get(.view = &old, .index = 0)
}
