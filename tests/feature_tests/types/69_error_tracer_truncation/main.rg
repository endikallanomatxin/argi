..truncated_test_failure
fail() -> !Void := { result = ..error(.reason = ..truncated_test_failure) }
main(.system: System) -> (.status_code: Int32) := {
    tracer ::= unwrap_or_abort(.value = FixedSizeErrorTracer(.allocator = system.page_allocator, .size = 288))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= fail()
    add_context(.context = "discarded")
    add_context(.context = "latest")
    match failed {
        ..ok _ { status_code = 1 }
        ..error & err {
            reported ::= report_trace(.trace = &err&.trace, .stderr = system.terminal&.stderr_file)
            match reported { ..ok _ { status_code = 0 } ..error _ { status_code = 2 } }
        }
    }
}
