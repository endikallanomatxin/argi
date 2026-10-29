escape := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: $&Virtual#(ErrorTracer)) {
    assume error_tracer
    tracer ::= NoopErrorTracer()
    virtual_tracer ::= to_virtual#(ErrorTracer)($&tracer)
    result = $&virtual_tracer
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    escaped ::= escape()
}
