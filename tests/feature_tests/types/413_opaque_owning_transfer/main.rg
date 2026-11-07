main := (.system: System) -> () {
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= Virtual#(Allocator)($&allocator_provider)
    text ::= unwrap_or_abort(.value = String(.length = 1))
    array ::= unwrap_or_abort(.value = DynamicArray#(String)(.capacity = 1))
    push_assume_capacity(.self = $&array, .value = ~text)
    selected ::= unwrap_or_abort(.value = get_reference(.self = &array, .index = 0))
    if unwrap_or_abort(.value = bytes_get(.view = selected, .index = 0)) != 0 { abort }
}
