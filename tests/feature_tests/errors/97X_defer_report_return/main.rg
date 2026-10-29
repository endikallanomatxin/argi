fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    defer { fail()!!! }
}
