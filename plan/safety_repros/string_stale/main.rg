append := (.destination: $&String, .count: UIntNative, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Void, (..invalid_ascii, ..out_of_memory))) {
    push_ascii(destination, .byte = 65, .allocator = allocator)!
    push_ascii(destination, .byte = 65, .allocator = allocator)!
    result = ..ok Void()
}

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    text ::= unwrap_or_abort(string_with_capacity(.allocator = allocator, .capacity = 0))
    saved ::= view(&text)
    unwrap_or_abort(append(.destination = $&text, .count = 2, .allocator = allocator))
    observed ::= byte_data(.text = saved).reference&
}
