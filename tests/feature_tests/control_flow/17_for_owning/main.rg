Tracked: Type = (.id: Int32)

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

return_early(.array: DynamicArray#(.t: Tracked), .allocator: $&PageAllocator) -> () := {
    assume allocator
    for ~item in array { return }
}

..iteration_failed

fail_early(
        .array     : DynamicArray#(.t: Tracked),
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..iteration_failed)) = ..ok Void()
    ) := {
    assume allocator
    for ~item in array {
        result = ..error(.reason = ..iteration_failed)
        return
    }
}

make_array(.allocator: $&PageAllocator) -> !DynamicArray#(.t: Int32) := {
    assume allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 1)!
    push(.self = $&array, .value = 42, .allocator = allocator)!
    result = ..ok ~array
}

iteration_error() -> (.result: Errable#(.t: Void, .reasons: (..iteration_failed))) := {
    result = ..error(.reason = ..iteration_failed)
}

propagate_early(
        .array     : DynamicArray#(.t: Tracked),
        .allocator : $&PageAllocator
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..iteration_failed)) = ..ok Void()
    ) := {
    assume allocator
    for ~item in array { iteration_error()! }
}

Pair: Type = (.first: Tracked, .second: Tracked)

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 3)!
    push(.self = $&array, .value = 1, .allocator = allocator)!
    push(.self = $&array, .value = 2, .allocator = allocator)!
    push(.self = $&array, .value = 3, .allocator = allocator)!
    expected :: Int32 = 1
    for ~item in array {
        if item != expected { abort }
        expected = expected + 1
    }
    if expected != 4 { abort }
    owners ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 3)!
    push(.self = $&owners, .value = Tracked(.id = 1), .allocator = allocator)!
    push(.self = $&owners, .value = Tracked(.id = 2), .allocator = allocator)!
    push(.self = $&owners, .value = Tracked(.id = 3), .allocator = allocator)!
    for ~owner in owners {
        if owner.id != 1 { abort }
        break
    }
    if drops != 3 { abort }
    deque ::= Deque#(.t: Tracked)(.allocator = allocator)!
    push_back(.self = $&deque, .value = Tracked(.id = 4), .allocator = allocator)!
    push_back(.self = $&deque, .value = Tracked(.id = 5), .allocator = allocator)!
    for ~owner in deque {
        if owner.id != 4 { abort }
        break
    }
    if drops != 5 { abort }

    early ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&early, .value = Tracked(.id = 6), .allocator = allocator)!
    push(.self = $&early, .value = Tracked(.id = 7), .allocator = allocator)!
    return_early(.array = ~early, .allocator = allocator)
    if drops != 7 { abort }
    failing ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&failing, .value = Tracked(.id = 8), .allocator = allocator)!
    push(.self = $&failing, .value = Tracked(.id = 9), .allocator = allocator)!
    match fail_early(.array = ~failing, .allocator = allocator) { ..ok _ { abort } ..error _ {} }
    if drops != 9 { abort }
    empty ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 0)!
    for ~item in empty { abort }

    for ~item in make_array(.allocator = allocator)! {
        if item != 42 { abort }
    }
    continued ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&continued, .value = Tracked(.id = 10), .allocator = allocator)!
    push(.self = $&continued, .value = Tracked(.id = 11), .allocator = allocator)!
    for ~item in continued { continue }
    if drops != 11 { abort }

    propagated ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&propagated, .value = Tracked(.id = 12), .allocator = allocator)!
    push(.self = $&propagated, .value = Tracked(.id = 13), .allocator = allocator)!
    match propagate_early(.array = ~propagated, .allocator = allocator) {
        ..ok _ { abort } ..error _ {}
    }
    if drops != 13 { abort }
    pairs ::= DynamicArray#(.t: Pair)(.allocator = allocator, .capacity = 2)!
    push(
        .self      = $&pairs
        .value     = (.first = Tracked(.id = 14), .second = Tracked(.id = 15))
        .allocator = allocator
    )!
    push(
        .self      = $&pairs
        .value     = (.first = Tracked(.id = 16), .second = Tracked(.id = 17))
        .allocator = allocator
    )!
    for ~pair in pairs { break }
    if drops != 17 { abort }
    source ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    target ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&source, .value = Tracked(.id = 18), .allocator = allocator)!
    push(.self = $&source, .value = Tracked(.id = 19), .allocator = allocator)!
    for ~item in source { push(.self = $&target, .value = ~item, .allocator = allocator)! }
    if drops != 17 { abort }
    deinit(.self = $&target, .allocator = allocator)
    if drops != 19 { abort }

}
