main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    left :: Float32 = 1.0
    value ::= checked_multiply(.left = left, .right = left)
}
