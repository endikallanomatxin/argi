main := (.system: System) -> () {
    assume allocator ::= system.page_allocator

    text ::= unwrap_or_abort(.value = String(.length = 4))
    borrowed ::= view(&text)
    clear($&text)
    _ ::= bytes_get(.view = &borrowed, .index = 0)
}
