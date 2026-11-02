fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!Void = ..ok Void() {
    assume error_tracer
}

finish := #(.t: Type) (.value: t, .error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    defer fail()!! "cleanup"
}

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    finish#(.t: Int32)(1)
}
