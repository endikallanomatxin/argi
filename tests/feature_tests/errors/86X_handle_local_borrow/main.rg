..missing

attempt := (
    .value        : &Int32,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: &Int32, .reasons: (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> () {
    source :: Int32 = 7
    pointer ::= attempt(.value = &source) handle error, value {
        local :: Int32 = 9
        value = &local
    }
    observed ::= pointer&
}
