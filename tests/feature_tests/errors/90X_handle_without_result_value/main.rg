..missing

attempt := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Int32, (..missing))) {
    assume error_tracer
    result = ..ok 7
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    value: Int32 = attempt() handle error {}
}
