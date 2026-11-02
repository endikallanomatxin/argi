test selected := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    #if 1 < 2 {
        testing.expect_with_trace(.condition = true)!
    } #else {
        unavailable_test_branch()
    }
}
