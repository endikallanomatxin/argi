produce := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..test_error))
) {
    assume error_tracer

    result = ..ok Void()
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    result ::= produce()
    if is(.value = result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    status_code = 0
}
