..missing

fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32, .reasons: (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> (.status_code: Int32 = 0) {
    number ::= fail() handle error, value {}
    status_code = number
}
