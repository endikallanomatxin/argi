fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type) (.value: t, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Int32 = 0
) {
    assume error_tracer
    defer { fail()!!! { result = 1 } }
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    finish#(.t: Int32)(1)
}
