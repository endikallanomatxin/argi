main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    success: Errable#(.t: Void) = ..ok Void()
    success!!!
    status_code = 0
}
