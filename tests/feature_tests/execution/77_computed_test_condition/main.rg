test selected := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer

    #if 1 < 2 {
        testing.expect(.condition = true)!
    } #else {
        unavailable_test_branch()
    }
}
