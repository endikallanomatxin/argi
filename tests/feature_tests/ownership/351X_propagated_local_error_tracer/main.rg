..failure

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!Void {
    assume error_tracer

    result = ..error(.reason = ..failure)
}

escape := () -> !!Void = ..ok Void() {
    tracer ::= NoopErrorTracer()
    virtual_tracer ::= to_virtual#(ErrorTracer)($&tracer)
    assume error_tracer ::= $&virtual_tracer

    fail()!
}

main := () -> () {
    error ::= escape()
}
