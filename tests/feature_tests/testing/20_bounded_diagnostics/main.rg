test bounded_message := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect_with_trace(
        .condition = false
        .message   = "context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context context "
    )!
}
