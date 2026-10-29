fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

main := () -> () { defer { fail() handle error { return } } }
