..file_not_found

some_fallible_call := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Void, .reasons: (..file_not_found))) {
    assume error_tracer

    result = ..error(.reason = ..file_not_found)
}

test direct_propagation := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    some_fallible_call()!
}
