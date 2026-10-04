python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    values: [3]Int32 = (10, 20, 30)
    converted ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = &values)).result
    if unwrap_or_abort(.value = python.length(.self = &converted)).result != 3 { abort }
    index: Int32 = 1
    key ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = index)).result
    element ::= unwrap_or_abort(.value = python.get_item(.self = &converted, .key = &key)).result
    if unwrap_or_abort(.value = python.to_int64(.self = &element)).result != 20 { abort }
    named: [1]python.Keyword = ((.name = "values", .value = &converted))
    keywords ::= unwrap_or_abort(.value = python.keyword_arguments(.self = &interpreter,
            .values = view(.array = &named))).result
    name ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = "values")).result
    stored ::= unwrap_or_abort(.value = python.get_item(.self = &keywords, .key = &name)).result
    if unwrap_or_abort(.value = python.length(.self = &stored)).result != 3 { abort }
    empty: [0]Int64 = ()
    empty_list ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = &empty)).result
    if unwrap_or_abort(.value = python.length(.self = &empty_list)).result != 0 { abort }
    nested: [2][2]Int16 = ((1, 2), (3, 4))
    nested_object ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter,
            .value = &nested)).result
    if unwrap_or_abort(.value = python.length(.self = &nested_object)).result != 2 { abort }
    dynamic ::= unwrap_or_abort(.value = DynamicArray#(.t: UInt8)(.allocator = system.page_allocator,

            .capacity = 1)).result
    byte: UInt8 = 7
    unwrap_or_abort(.value = push(.self = $&dynamic, .value = byte,
            .allocator = system.page_allocator))
    dynamic_object ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter,
            .value = &dynamic)).result
    if unwrap_or_abort(.value = python.length(.self = &dynamic_object)).result != 1 { abort }
    real: Float32 = 1.5
    real_object ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = real)).result
    expected: Float64 = 1.5
    if unwrap_or_abort(.value = python.to_float64(.self = &real_object)).result != expected {
        abort
    }
    json ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "json")).result
    dumps ::= unwrap_or_abort(.value = python.attribute(.self = &json, .name = "dumps")).result
    call_values: [1]python.Argument = (..object&converted)
    call_arguments ::= unwrap_or_abort(.value = python.positional_arguments(.self = &interpreter,
            .values = view(.array = &call_values))).result
    named_values: [1]python.NamedArgument = ((.name = "indent", .value = ..integer 2))
    named_arguments ::= unwrap_or_abort(.value = python.keyword_arguments(.self = &interpreter,
            .values = view(.array = &named_values))).result
    rendered ::= unwrap_or_abort(.value = python.call(.self = &dumps, .arguments = &call_arguments,
            .keywords = ..some(.value = &named_arguments))).result
    text ::= unwrap_or_abort(.value = python.to_string(.self = &rendered,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &text).view, .pattern = "\n  10,").ok == false { abort }
}
