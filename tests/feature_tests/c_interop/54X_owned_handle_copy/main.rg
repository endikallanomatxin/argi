owned := import ("../../_support/owned_foreign_handle")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    handle ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 42))
    duplicate := handle
}
