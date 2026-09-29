..test_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

middle() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := fail()!
    result = ..ok value
}

top() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := middle() !! "reading config"
    result = ..ok value
}

main(.system: System) -> (.status_code: Int32) := {
    assume stderr ::= system.terminal&.stderr_file
    assume error_tracer ::= unwrap_or_abort(
        .value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 4096),
    ) | to_virtual#(ErrorTracer)($&_) | $&_
    result := top()

    if is(.value = result, .variant = ..error) {
        err ::= &result..error
        report_trace(.trace = &err&.trace)
        status_code = 0
    } else {
        status_code = 1
    }
}
