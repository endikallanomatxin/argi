python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    numpy ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "numpy")).result
    arange ::= unwrap_or_abort(.value = python.attribute(.self = &numpy, .name = "arange")).result
    count: Int64 = 5
    stop ::= unwrap_or_abort(.value = python.integer(.self = &interpreter, .value = count)).result
    arguments: [1]&python.Object = (&stop)
    array ::= unwrap_or_abort(.value = python.call(.self = &arange,
            .arguments = view(.array = &arguments))).result
    tolist ::= unwrap_or_abort(.value = python.attribute(.self = &array, .name = "tolist")).result
    values ::= unwrap_or_abort(.value = python.call(.self = &tolist)).result
    if unwrap_or_abort(.value = python.length(.self = &values)).result != 5 { abort }
    index: Int64 = 4
    key ::= unwrap_or_abort(.value = python.integer(.self = &interpreter, .value = index)).result
    last ::= unwrap_or_abort(.value = python.get_item(.self = &values, .key = &key)).result
    if unwrap_or_abort(.value = python.to_int64(.self = &last)).result != 4 { abort }
}
