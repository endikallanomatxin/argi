python := import ("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    values: [1]Int64 = (1)
    object ::= unwrap_or_abort(.value = python.numeric_buffer(.self = &interpreter,
            .values = view(.array = &values))).result
    python.copy_numeric(.self = &object, .destination = view(.array = &values))
}
