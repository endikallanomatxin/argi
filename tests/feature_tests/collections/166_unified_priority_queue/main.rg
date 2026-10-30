main := () -> (.status_code: Int32 = 1) {
    assume ffi ::= $&ForeignFunctionInterface()

    allocator_storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&allocator_storage
    order ::= Int32OrderPolicy()
    queue ::= unwrap_or_abort(
        .value = PriorityQueue#(.t: Int32)(.order = &order, .capacity = 1)
    )
    if is(.value = peek_reference(&queue).value, .variant = ..some) { abort }
    if is(.value = pop($&queue).result, .variant = ..some) { abort }
    index :: Int32 = 64
    while index > 0 {
        index = index - 1
        unwrap_or_abort(.value = push($&queue, .value = index % 16))
    }
    index = 0
    while index < 64 {
        expected ::= index / 4
        match peek_reference(&queue).value {
            ..none { abort }
            ..some item { if item.value&!= expected { abort } }
        }
        match peek(&queue).value {
            ..none { abort }
            ..some item { if item.value != expected { abort } }
        }
        match pop($&queue).result {
            ..none { abort }
            ..some item { if item.value != expected { abort } }
        }
        index = index + 1
    }
    if length(&queue).count != 0 { abort }
    status_code = 0
}
