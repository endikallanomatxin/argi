fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..ok Void() {
    assume error_tracer
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    defer { fail()!!! { status_code = 1 } }
}
