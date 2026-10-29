run := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Int32 {
    assume error_tracer

    dep := import ("./dep")
    value := dep.load()!
    result = ..ok value
}

main := () -> (.status_code: Int32) {
    outcome := run()

    match outcome {
        ..ok payload {
            status_code = payload
            return
        }
        ..error&err {
            match err&.reason {
                ..import_error {
                    status_code = 46
                    return
                }
            }
        }
    }
}
