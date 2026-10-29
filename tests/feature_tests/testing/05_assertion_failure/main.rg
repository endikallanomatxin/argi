test assertion_failure := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    testing.expect(.condition = false)!
}
