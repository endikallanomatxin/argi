owned := import ("../../_support/owned_foreign_handle")

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    capability ::= ForeignFunctionInterface()
    assume ffi := $&capability
    handle ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 42))
    moved ::= ~capability
}
