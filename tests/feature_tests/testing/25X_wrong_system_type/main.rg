test wrong_system_type := (.system: Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer
}
