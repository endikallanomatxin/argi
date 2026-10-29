..import_error

fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32, .reasons: (..import_error))) {
    assume error_tracer

    result = ..error(.reason = ..import_error)
}

load := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32)) {
    assume error_tracer

    value := fail()!
    result = ..ok value
}
