fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

main := () -> (.status_code: Int32 = 0) { defer { fail()!!! { status_code = 1 } } }
