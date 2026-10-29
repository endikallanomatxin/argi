python := import ("python")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    value ::= unwrap_or_abort(.value = python.none(.self = &interpreter)).result
    copy ::= value
    python.is_none(.self = &copy)
}
