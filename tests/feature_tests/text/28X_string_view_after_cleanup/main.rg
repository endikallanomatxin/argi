main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 32))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 97))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 32))
    view ::= view(.self = &text).view
    deinit(.self = $&text)
    observed ::= byte_data(.text = view).reference&
}
