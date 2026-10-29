test skips_without_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    testing.skip(.message = "no system requested")!
}
