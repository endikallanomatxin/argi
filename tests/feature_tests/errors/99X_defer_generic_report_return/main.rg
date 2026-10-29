fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type, .WriterType: Type: Writer#(WriterType)) (
    .value: t, .writer: $&WriterType, .error_tracer: $&Virtual#(ErrorTracer)
) -> () {
    assume error_tracer
    defer { fail()!!! }
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    finish#(.t: Int32)(1)
}
