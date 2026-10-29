..missing

attempt := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Int32, (..missing))) {
    assume error_tracer
    result = ..ok 7
}

main := () -> () {
    value: Int32 = attempt() handle error {}
}
