..truncated_test_failure

fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Void {
    assume error_tracer
    result = ..error(.reason = ..truncated_test_failure)
}

main := (.system: System) -> (.status_code: Int32) {
    tracer ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [288]UInt8)()))
    virtual_tracer ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= fail()
    add_context_text(.context = "discarded")
    add_context_text(.context = "latest")
    match failed {
        ..ok _ { status_code = 1 }
        ..error&err {
            reported ::= report_trace(
                .tracer = err&.tracer, .writer = $&system.terminal&.stderr
            )
            match reported { ..ok _ { status_code = 0 } ..error _ { status_code = 2 } }
        }
    }
}
