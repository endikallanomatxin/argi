test fails_without_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect(.condition = false)!
}
