main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    value :: Int32 = 7
    address ::= $&value | convert#(.to: UIntNative)(_)
    reference ::= cast#(.to: $&Int32)(.value = address)
    status_code = reference&- 7
}
