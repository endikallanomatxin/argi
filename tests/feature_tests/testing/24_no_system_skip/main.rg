test skips_without_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.skip_with_trace(.message = "no system requested")!
}
