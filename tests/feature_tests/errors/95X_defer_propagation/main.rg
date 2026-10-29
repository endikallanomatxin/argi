fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..ok Void() {
    assume error_tracer
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    defer fail()!
}
