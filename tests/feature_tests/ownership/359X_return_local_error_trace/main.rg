escape := () -> (.result: $&Virtual#(ErrorTracer)) {

    tracer ::= NoopErrorTracer()
    virtual_tracer ::= Virtual#(ErrorTracer)($&tracer)
    result = $&virtual_tracer
}

main := () -> () {

    escaped ::= escape()
}
