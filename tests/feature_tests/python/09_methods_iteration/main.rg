python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    types ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "types")).result
    namespace ::= unwrap_or_abort(.value = python.call_method(.self = &types,
            .name = "SimpleNamespace")).result
    number: Int32 = 42
    value ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = number)).result
    unwrap_or_abort(.value = python.set_attribute(.self = &namespace, .name = "answer",
            .value = &value))
    attribute ::= unwrap_or_abort(.value = python.attribute(.self = &namespace, .name = "answer")).result
    if unwrap_or_abort(.value = python.to_int64(.self = &attribute)).result != 42 { abort }
    refs: [2]&python.Object = (&value, &attribute)
    tuple ::= unwrap_or_abort(.value = python.tuple(.self = &interpreter,
            .values = view(.array = &refs))).result
    iterator ::= unwrap_or_abort(.value = python.iterate(.self = &tuple)).result
    count :: UIntNative = 0
    while true {
        item ::= unwrap_or_abort(.value = python.next(.self = $&iterator)).result
        match item {
            ..none { break }
            ..some ~payload {
                if unwrap_or_abort(.value = python.to_int64(.self = &payload.value)).result != 42 {
                    abort
                }
                count = count + 1
            }
        }
    }
    if count != 2 { abort }
    match python.next(.self = $&iterator).result {
        ..ok ~value { match value { ..none {} ..some _ { abort } } } ..error _ { abort }
    }
    match python.call_method(.self = &namespace, .name = "missing") {
        ..error _ {} ..ok _ { abort }
    }
    match python.iterate(.self = &value) { ..error _ {} ..ok _ { abort } }
    text ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = "abc")).result
    upper ::= unwrap_or_abort(.value = python.call_method(.self = &text, .name = "upper")).result
    result ::= unwrap_or_abort(.value = python.to_string(.self = &upper,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &result).view, .pattern = "ABC").ok == false { abort }
    builtins ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter,
            .name = "builtins")).result
    int_type ::= unwrap_or_abort(.value = python.attribute(.self = &builtins, .name = "int")).result
    invalid_values: [1]StringView = ("not an integer")
    invalid_list ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter,
            .value = &invalid_values)).result
    map_arguments: [2]&python.Object = (&int_type, &invalid_list)
    mapped ::= unwrap_or_abort(.value = python.call_method(.self = &builtins, .name = "map",
            .arguments = view(.array = &map_arguments))).result
    failing_iterator ::= unwrap_or_abort(.value = python.iterate(.self = &mapped)).result
    match python.next(.self = $&failing_iterator) { ..error _ {} ..ok _ { abort } }
    error ::= unwrap_or_abort(.value = python.error_text(.self = &interpreter,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &error).view, .pattern = "ValueError").ok == false { abort }
}
