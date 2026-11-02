test skipped_case := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.skip_with_trace(.message = "not implemented yet")!
}
