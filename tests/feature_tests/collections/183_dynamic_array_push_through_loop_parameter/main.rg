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

check := (.system: System, .capacity: UIntNative) -> () {
    assume ffi := system.ffi
    backing ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= Virtual#(Allocator)($&backing)
    destination ::= unwrap_or_abort(DynamicArray#(UIntNative)(.allocator = allocator, .capacity = capacity))
    unwrap_or_abort(append(.destination = $&destination, .count = 2, .allocator = allocator))
    if unwrap_or_abort(get(&destination, .index = 1)) != 1 { abort }
}

main := (.system: System) -> () {
    check(.system = system, .capacity = 0)
    check(.system = system, .capacity = 2)
}
