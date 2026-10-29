test without_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    testing.expect_equal(
        .expected = 42
        .actual   = #run () -> (.value: Int32) {
            value = 42
        }
    )!
}

test with_system := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    testing.expect(true)!
}
