..missing

attempt := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> (.status_code: Int32 = 0) { attempt() handle error { abort } }
