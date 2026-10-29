fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type, .WriterType: Type: Writer#(WriterType)) (.value: t, .writer: $&WriterType) -> (
) { defer { fail()!!! } }

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    finish#(.t: Int32)(1)
}
