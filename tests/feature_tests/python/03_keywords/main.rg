python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    json ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "json")).result
    dumps ::= unwrap_or_abort(.value = python.attribute(.self = &json, .name = "dumps")).result
    data ::= unwrap_or_abort(.value = python.list(.self = &interpreter)).result
    value: Int64 = 42
    number ::= unwrap_or_abort(.value = python.integer(.self = &interpreter, .value = value)).result
    unwrap_or_abort(.value = python.append(.self = &data, .value = &number))
    keywords ::= unwrap_or_abort(.value = python.dictionary(.self = &interpreter)).result
    key ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "indent")).result
    indent_value: Int64 = 2
    indent ::= unwrap_or_abort(.value = python.integer(.self = &interpreter, .value = indent_value)).result
    unwrap_or_abort(.value = python.set_item(.self = &keywords, .key = &key, .value = &indent))
    arguments: [1]&python.Object = (&data)
    rendered ::= unwrap_or_abort(.value = python.call(.self = &dumps,
            .arguments = view(.array = &arguments), .keywords = ..some(.value = &keywords))).result
    text ::= unwrap_or_abort(.value = python.to_string(.self = &rendered,
            .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &text).view, .pattern = "\n  42\n").ok == false { abort }
    builtins ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter,
            .name = "builtins")).result
    factory ::= unwrap_or_abort(.value = python.attribute(.self = &builtins, .name = "list")).result
    empty ::= unwrap_or_abort(.value = python.call(.self = &factory)).result
    if unwrap_or_abort(.value = python.length(.self = &empty)).result != 0 { abort }
}
