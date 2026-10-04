python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    truth ::= unwrap_or_abort(.value = python.boolean(.self = &interpreter, .value = true)).result
    if unwrap_or_abort(.value = python.to_bool(.self = &truth)).result == false { abort }
    match python.to_int64(.self = &truth) { ..error _ {} ..ok _ { abort } }
    error ::= unwrap_or_abort(.value = python.error_text(.self = &interpreter,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &error).view, .pattern = "TypeError").ok == false { abort }
    signed_value: Int64 = -42
    unsigned_value: UInt64 = 18446744073709551615
    float_value: Float64 = 2.5
    square_value: Float64 = 9.0
    root_value: Float64 = 3.0
    number ::= unwrap_or_abort(.value = python.integer(.self = &interpreter, .value = signed_value)).result
    if unwrap_or_abort(.value = python.to_int64(.self = &number)).result != -42 { abort }
    match python.to_uint64(.self = &number) { ..error _ {} ..ok _ { abort } }
    unsigned ::= unwrap_or_abort(.value = python.integer(.self = &interpreter,
            .value = unsigned_value)).result
    if unwrap_or_abort(.value = python.to_uint64(.self = &unsigned)).result != 18446744073709551615 {
        abort
    }
    match python.to_int64(.self = &unsigned) { ..error _ {} ..ok _ { abort } }
    real ::= unwrap_or_abort(.value = python.floating(.self = &interpreter, .value = float_value)).result
    if unwrap_or_abort(.value = python.to_float64(.self = &real)).result != float_value { abort }
    nothing ::= unwrap_or_abort(.value = python.none(.self = &interpreter)).result
    if unwrap_or_abort(.value = python.is_none(.self = &nothing)).result == false { abort }
    sequence ::= unwrap_or_abort(.value = python.list(.self = &interpreter)).result
    unwrap_or_abort(.value = python.append(.self = &sequence, .value = &number))
    if unwrap_or_abort(.value = python.length(.self = &sequence)).result != 1 { abort }
    key ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "value")).result
    dictionary ::= unwrap_or_abort(.value = python.dictionary(.self = &interpreter)).result
    unwrap_or_abort(.value = python.set_item(.self = &dictionary, .key = &key, .value = &sequence))
    fetched ::= unwrap_or_abort(.value = python.get_item(.self = &dictionary, .key = &key)).result
    duplicate ::= unwrap_or_abort(.value = python.clone(.self = &fetched)).result
    if unwrap_or_abort(.value = python.length(.self = &duplicate)).result != 1 { abort }
    text ::= unwrap_or_abort(.value = python.to_string(.self = &key,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &text).view, .pattern = "value").ok == false { abort }
    unicode ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "á🙂")).result
    unicode_copy ::= unwrap_or_abort(.value = python.to_string(.self = &unicode,
            .allocator = system.page_allocator)).result
    if unicode_copy.length != 6 { abort }
    if contains(.self = as_view(.self = &unicode_copy).view, .pattern = "á🙂").ok == false {
        abort
    }
    binary ::= unwrap_or_abort(.value = python.bytes(.self = &interpreter, .value = "a\0b")).result
    copied ::= unwrap_or_abort(.value = python.to_bytes(.self = &binary,
            .allocator = system.page_allocator)).result
    if copied.length != 3 { abort }
    representation ::= unwrap_or_abort(.value = python.repr(.self = &dictionary)).result
    rendered ::= unwrap_or_abort(.value = python.to_string(.self = &representation,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &rendered).view, .pattern = "-42").ok == false { abort }
    match python.import_module(.self = &interpreter, .name = "argi_module_that_does_not_exist") {
        ..error _ {} ..ok _ { abort }
    }
    captured ::= unwrap_or_abort(.value = python.error_text(.self = &interpreter,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &captured).view, .pattern = "ModuleNotFoundError").ok == false {
        abort
    }
    json ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "json")).result
    loads ::= unwrap_or_abort(.value = python.attribute(.self = &json, .name = "loads")).result
    invalid ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "{")).result
    arguments: [1]&python.Object = (&invalid)
    match python.call(.self = &loads, .arguments = view(.array = &arguments)) {
        ..error _ {} ..ok _ { abort }
    }
    traceback ::= unwrap_or_abort(.value = python.error_text(.self = &interpreter,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &traceback).view, .pattern = "Traceback").ok == false {
        abort
    }
    if contains(.self = as_view(.self = &traceback).view, .pattern = "JSONDecodeError").ok == false {
        abort
    }
    math ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "math")).result
    sqrt ::= unwrap_or_abort(.value = python.attribute(.self = &math, .name = "sqrt")).result
    square ::= unwrap_or_abort(.value = python.floating(.self = &interpreter, .value = square_value)).result
    sqrt_arguments: [1]&python.Object = (&square)
    root ::= unwrap_or_abort(.value = python.call(.self = &sqrt,
            .arguments = view(.array = &sqrt_arguments))).result
    if unwrap_or_abort(.value = python.to_float64(.self = &root)).result != root_value { abort }
}
