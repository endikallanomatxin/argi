setup := once () -> () {
}

helper := () -> () {
    setup()
}

test first := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    helper()
}

test second := (
    .system       : System,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !() {
    assume error_tracer

    helper()
}
