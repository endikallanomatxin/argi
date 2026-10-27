main := (.system: System) -> ()  {
    assume allocator := system.page_allocator
    text ::= unwrap_or_abort(.value = string_with_capacity(.capacity = 8))
    unwrap_or_abort(.value = push_ascii($&text, .byte = 65))
    old ::= view(&text)
    unwrap_or_abort(.value = push_ascii($&text, .byte = 66))
    _ ::= bytes_get(.view = &old, .index = 0)
}
