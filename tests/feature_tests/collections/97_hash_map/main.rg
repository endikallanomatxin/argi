main := () -> (.status_code: Int32 = 0) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&allocator_storage
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy(), .allocator = allocator
        )
    )
    index :: Int32 = 0
    while index < 40 {
        unwrap_or_abort(
            .value = put(
                .self = $&map, .key = index, .value = index * 3, .allocator = allocator
            )
        )
        index = index + 1
    }
    if length(.self = &map).count != 40 { abort }
    index = 0
    while index < 40 {
        match get(.self = &map, .key = &index).result {
            ..none { abort }
            ..some entry { if entry.value != index * 3 { abort } }
        }
        index = index + 1
    }
    unwrap_or_abort(.value = put(.self = $&map, .key = 2, .value = 999, .allocator = allocator))
    if length(.self = &map).count != 40 { abort }
    if remove(.self = $&map, .key = &1, .allocator = allocator).removed == false { abort }
    if remove(.self = $&map, .key = &1, .allocator = allocator).removed { abort }
    if contains(.self = &map, .key = &1).ok { abort }
    match get_reference(.self = &map, .key = &2).result {
        ..none { abort }
        ..some pointer { if pointer.value&!= 999 { abort } }
    }
    deinit(.self = $&map)
}
