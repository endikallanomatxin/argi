..truncated_test_failure
fail() -> !Void := { result = ..error(.reason = ..truncated_test_failure) }
main(.system: System) -> (.status_code: Int32) := {
    tracer ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [288]UInt8)()))
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= fail()
    add_context(.context = "discarded")
    add_context(.context = "latest")
    match failed {
        ..ok _ { status_code = 1 }
        ..error & err {
            reported ::= report_trace(.trace = &err&.trace, .writer = $&system.terminal&.stderr)
            match reported { ..ok _ { status_code = 0 } ..error _ { status_code = 2 } }
        }
    }
}
