Buffers := (.a: DynamicArray#(UIntNative), .b: DynamicArray#(UIntNative))
push_both := (.a: $&DynamicArray#(UIntNative), .b: $&DynamicArray#(UIntNative), .allocator: Virtual#(Allocator)) -> (.result: Errable#(Void, (..out_of_memory))) {
    push(a, .value = 0, .allocator = allocator)!
    push(b, .value = 0, .allocator = allocator)!
    result = ..ok Void()
}

make := (.allocator: Virtual#(Allocator), .count: UIntNative) -> (.result: Errable#(Buffers, (..out_of_memory))) {
    a ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    b ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = count)!
    push_both(.a = $&a, .b = $&b, .allocator = allocator)!
    result = ..ok(.a = ~a, .b = ~b)
}
main := (.system: System) -> () {
    buffers ::= unwrap_or_abort(make(.allocator = system.page_allocator, .count = length(system.args).count))
    deinit(.self = $&buffers.a)
    if unwrap_or_abort(get(&buffers.b, .index = 0)) != 0 { abort }
}
