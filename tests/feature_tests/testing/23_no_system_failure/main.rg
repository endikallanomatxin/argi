test fails_without_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect_with_trace(.condition = false)!
}
