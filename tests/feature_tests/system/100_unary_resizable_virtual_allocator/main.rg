append := #(.Collection: Type: Resizable#(.Item: Int32)) (
    .items: $&Collection, .allocator: $&Virtual#(Allocator), .value: Int32
) -> () {
    unwrap_or_abort(Resizable#(Collection).push(items, .value = value, .allocator = allocator))
    unwrap_or_abort(
        Resizable#(Collection).insert(items, .index = 0, .value = value + 1, .allocator = allocator)
    )
}

main := () -> (.status_code: Int32 = 0) {
    assume ffi ::= $&ForeignFunctionInterface()
    first ::= CAllocator(.ffi = ffi)
    second ::= CAllocator(.ffi = ffi)
    first_handle ::= to_virtual#(Allocator)($&first)
    second_handle ::= to_virtual#(Allocator)($&second)

    items ::= unwrap_or_abort(DynamicArray#(Int32)(.allocator = $&first_handle, .capacity = 1))
    append(.items = $&items, .allocator = $&first_handle, .value = 3)
    append(.items = $&items, .allocator = $&second_handle, .value = 5)
    if length(&items).count != 4 { abort }
    if unwrap_or_abort(get_reference(&items, .index = 0))&!= 6 { abort }
    if unwrap_or_abort(get_reference(&items, .index = 3))&!= 5 { abort }
}
