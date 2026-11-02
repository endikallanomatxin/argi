test installed_prefix := () -> !() {
    testing.expect(.condition = true)!
}

test installed_trace := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer
    testing.expect_with_trace(.condition = true)!
}
