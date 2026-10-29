fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type) (.value: t) -> (.result: Int32 = 0) {
    defer { fail()!!! { result = 1 } }
}

main := () -> () { finish#(.t: Int32)(1) }
