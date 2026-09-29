..test_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

middle() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := fail()!
    result = ..ok value
}

top() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := middle() !! "loading project config"
    result = ..ok value
}

main(.system: System) -> (.status_code: Int32) := {
    assume stderr ::= system.terminal&.stderr_file
    tracer ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 4096))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    result := top()

    if is(.value = result, .variant = ..error) {
        err ::= &result..error
        report_error(.message = "project build failed", .err = err)
        status_code = 0
    } else {
        status_code = 1
    }
}
