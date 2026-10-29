..missing

fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Int32, (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

recover := (.initialize: Bool) -> (.result: Int32) {
    result = fail() handle error, value {
        if initialize { value = 7 }
    }
}

main := () -> () { recover(false) }
