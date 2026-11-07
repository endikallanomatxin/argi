main := (.system: System) -> () {
    allocator_provider ::= CAllocator(.ffi = system.ffi)
    assume allocator ::= to_virtual#(Allocator)($&allocator_provider)
    text ::= unwrap_or_abort(.value = String(.length = 1))
    borrowed ::= unwrap_or_abort(.value = string_byte_reference(.string = &text, .index = 0))
    deinit(.self = $&text)
    array ::= unwrap_or_abort(.value = DynamicArray#(&UInt8)(.capacity = 1))
    push_assume_capacity(.self = $&array, .value = borrowed)
    selected ::= unwrap_or_abort(.value = get_reference(.self = &array, .index = 0))
    if selected&& != 0 { abort }
}
