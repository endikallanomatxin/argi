setup := once () -> () {
}

helper := () -> () {
    setup()
}

test first := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    helper()
}

test second := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    helper()
}
