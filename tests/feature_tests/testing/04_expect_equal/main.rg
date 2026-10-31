test equality := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect_equal_with_trace(.expected = 1, .actual = 1)!
}
