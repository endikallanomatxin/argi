main := () -> (.status_code: Int32) {
    status_code = 0
}

test ignored_during_build := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    testing.fail(.message = "tests must be excluded from argi build")!
}
