main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: UIntNative)(.allocator = allocator, .capacity = 1)!
    index :: UIntNative = 0
    while index < 65 {
        push(.self = $&array, .value = index, .allocator = allocator)!
        index = [
            index
            + 1
        ]
    }
    if capacity(.self = &array).count != 128 { abort }
    index = 0
    for item in array {
        if item != index { abort }
        index = index + 1
    }
    ensure_capacity(.self = $&array, .capacity = 129, .allocator = allocator)!
    if capacity(.self = &array).count != 256 { abort }
    oversized ::= integer_limits(.value = index).maximum
    match ensure_capacity(.self = $&array, .capacity = oversized, .allocator = allocator) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if length(.self = &array).count != 65 or capacity(.self = &array).count != 256 { abort }
}
