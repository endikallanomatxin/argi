python := import ("python")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    handle ::= interpreter._handle
}
