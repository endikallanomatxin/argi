..some_reason

some_fallible_call := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32, .reasons: (..some_reason))) {
    assume error_tracer

    result = ..error(.reason = ..some_reason)
}

test expected_error := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    call_result := some_fallible_call()
    testing.expect_error(.expected_reason = ..some_reason, .actual_result = ~call_result)!
}
