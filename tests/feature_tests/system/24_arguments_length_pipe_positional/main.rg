main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    argc ::= system.args | length(&_) | _.count

    if argc < 1 {
        status_code = 1
        return
    }

    status_code = 0
}
