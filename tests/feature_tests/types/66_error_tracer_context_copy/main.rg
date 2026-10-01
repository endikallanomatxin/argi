..copy_test_failure
fail() -> !Void := { result = ..error(.reason = ..copy_test_failure) }
context_failure(.allocator: $&PageAllocator) -> (.result: Errable#(.t: Void, .reasons: (..copy_test_failure))) := {
    text ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 3))
    bytes_set(.string = $&text, .index = 0, .value = 65)
    bytes_set(.string = $&text, .index = 1, .value = 66)
    bytes_set(.string = $&text, .index = 2, .value = 90)
    all ::= as_view(.self = &text)
    view :: StringView = (.data = all.data, .length = 2)
    fail() !! view
    result = ..ok Void()
}
main(.system: System) -> (.status_code: Int32) := {
    tracer ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 4096))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= context_failure(.allocator = system.page_allocator)
    match failed {
        ..ok _ { status_code = 1 }
        ..error & err {
            reported ::= report_trace(.trace = &err&.trace, .writer = $&system.terminal&.stderr)
            match reported { ..ok _ { status_code = 0 } ..error _ { status_code = 2 } }
        }
    }
}
