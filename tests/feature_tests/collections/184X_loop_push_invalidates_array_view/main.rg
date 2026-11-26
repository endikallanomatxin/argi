append := (
    .destination: $&DynamicArray#(UIntNative),
    .count: UIntNative,
    .allocator: Virtual#(Allocator)
) -> (.result: Errable#(Void, (..out_of_memory))) {
    index :: UIntNative = 0
    while index < count {
        push(destination, .value = index, .allocator = allocator)!
        index = index + 1
    }
    result = ..ok Void()
}

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    destination ::= unwrap_or_abort(DynamicArray#(UIntNative)(.allocator = allocator, .capacity = 1))
    push_assume_capacity($&destination, .value = 7)
    borrowed ::= view(&destination)
    unwrap_or_abort(append(.destination = $&destination, .count = 2, .allocator = allocator))
    if unwrap_or_abort(get(&borrowed, .index = 0)) != 7 { abort }
}
