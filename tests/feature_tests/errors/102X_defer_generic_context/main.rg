fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type) (.value: t) -> () { defer fail()!! "cleanup" }

main := () -> () { finish#(.t: Int32)(1) }
