run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    order ::= Int32OrderPolicy()
    queue ::= PriorityQueue#(.t: Int32, .order: Int32OrderPolicy)(
        .order     = &order
        .allocator = allocator
        .capacity  = 1
    )!
    match peek(.self = &queue).value { ..none {} ..some _ { abort } }
    match pop(.self = $&queue).value { ..none {} ..some _ { abort } }
    push(.self = $&queue, .value = 5, .allocator = allocator)!
    push(.self = $&queue, .value = -10, .allocator = allocator)!
    push(.self = $&queue, .value = 5, .allocator = allocator)!
    push(.self = $&queue, .value = 0, .allocator = allocator)!
    expected :: [4]Int32 = (-10, 0, 5, 5)
    index :: UIntNative = 0
    while index < 4 {
        match pop(.self = $&queue).value {
            ..none { abort }
            ..some item { if item.value != expected[index] { abort } }
        }
        index = index + 1
    }
    if length(.self = &queue).count != 0 { abort }
    value :: Int32 = 1024
    while value > 0 {
        push(.self = $&queue, .value = value, .allocator = allocator)!
        value = value - 1
    }
    value = 1
    while value <= 1024 {
        match peek(.self = &queue).value {
            ..none { abort }
            ..some item { if item.value != value { abort } }
        }
        match pop(.self = $&queue).value {
            ..none { abort }
            ..some item { if item.value != value { abort } }
        }
        value = value + 1
    }
    push(.self = $&queue, .value = -2147483648, .allocator = allocator)!
    push(.self = $&queue, .value = 2147483647, .allocator = allocator)!
    match pop(.self = $&queue).value {
        ..none { abort }
        ..some item { if item.value != -2147483648 { abort } }
    }
    match pop(.self = $&queue).value {
        ..none { abort }
        ..some item { if item.value != 2147483647 { abort } }
    }

}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
