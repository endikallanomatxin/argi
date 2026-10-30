test skipped_case := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.skip(.message = "not implemented yet")!
}
