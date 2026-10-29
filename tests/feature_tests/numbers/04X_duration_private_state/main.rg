main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    duration ::= Duration(.nanoseconds = 1)
    duration._nanoseconds = 2
}
