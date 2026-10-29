test selected := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    #if 1 < 2 {
        testing.expect(.condition = true)!
    } #else {
        unavailable_test_branch()
    }
}
