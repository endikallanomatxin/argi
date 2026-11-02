test simple_pass := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect_with_trace(.condition = true)!
}
