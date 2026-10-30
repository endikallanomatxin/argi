main := (.system: System) -> () {
    assume allocator ::= system.page_allocator

    text ::= unwrap_or_abort(.value = String())
    text._length = 100
}
