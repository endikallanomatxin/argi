test modern := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect(true)!
}

test multiline := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect_equal(.expected = 7, .actual = 7)!
}

-- Explicit empty input/output defaults use the same definition syntax.
test explicit := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    testing.expect(true)!
}
