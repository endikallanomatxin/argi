main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    generator ::= Pcg32(.seed = 42)
    generator._state = 0
}
