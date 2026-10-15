python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    values: [3]Int64 = (-1, 2, 300)
    storage ::= unwrap_or_abort(.value = python.numeric_buffer(.self = &interpreter,
            .values = view(.array = &values))).result
    builtins ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter,
            .name = "builtins")).result
    arguments: [1]&python.Object = (&storage)
    memory ::= unwrap_or_abort(.value = python.call_method(.self = &builtins, .name = "memoryview",
            .arguments = view(.array = &arguments))).result
    code ::= unwrap_or_abort(.value = python.to_object(.self = &interpreter, .value = "q")).result
    cast_arguments: [1]&python.Object = (&code)
    typed ::= unwrap_or_abort(.value = python.call_method(.self = &memory, .name = "cast",
            .arguments = view(.array = &cast_arguments))).result
    destination :: [4]Int64 = (99, 99, 99, 99)
    if unwrap_or_abort(.value = python.copy_numeric(.self = &typed,
            .destination = view(.array = $&destination))).result != 3 { abort }
    if destination[0] != -1 or destination[1] != 2 or destination[2] != 300 or destination[3] != 99 {
        abort
    }
    too_small :: [1]Int64 = (77)
    match python.copy_numeric(.self = &typed, .destination = view(.array = $&too_small)) {
        ..error _ {} ..ok _ { abort }
    }
    if too_small[0] != 77 { abort }
    unsigned :: [3]UInt64 = (55, 55, 55)
    match python.copy_numeric(.self = &typed, .destination = view(.array = $&unsigned)) {
        ..error _ {} ..ok _ { abort }
    }
    if unsigned[0] != 55 { abort }
    empty: [0]Float64 = ()
    empty_storage ::= unwrap_or_abort(.value = python.numeric_buffer(.self = &interpreter,
            .values = view(.array = &empty))).result
    if unwrap_or_abort(.value = python.length(.self = &empty_storage)).result != 0 { abort }
}
