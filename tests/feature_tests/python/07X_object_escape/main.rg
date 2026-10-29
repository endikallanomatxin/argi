python := import ("python")

make := (.ffi: $&ForeignFunctionInterface, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : python.Object
) {
    assume error_tracer
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = ffi)).result
    object ::= unwrap_or_abort(.value = python.none(.self = &interpreter)).result
    result = ~object
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    object ::= make(.ffi = system.ffi).result
    python.is_none(.self = &object)
}
