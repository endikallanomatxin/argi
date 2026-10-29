subtract := (.left: Int32, .right: Int32) -> (.diff: Int32) {
    diff = left - right
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    status_code = subtract(.left = 44, 2).diff
}
