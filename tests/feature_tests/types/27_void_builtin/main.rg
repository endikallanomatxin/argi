produce := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Void, .reasons: (..test_error))) {
    assume error_tracer

    result = ..ok Void()
}

main := () -> (.status_code: Int32) {
    result ::= produce()
    if is(.value = result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }

    status_code = 0
}
