..escape_test_failure
escape() -> !Void := {
    tracer ::= NoopErrorTracer()
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    result = ..error(.reason = ..escape_test_failure)
}
main() -> (.status_code: Int32) := {
    failed ::= escape()
    match failed { ..ok _ { status_code = 1 } ..error _ { status_code = 0 } }
}
