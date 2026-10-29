..missing

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..missing))
) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    number ::= fail() handle value, value { value = 0 }
}
