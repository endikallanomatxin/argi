main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    argc ::= length(.self = system.args).count

    if argc < 1 {
        status_code = 1
        return
    }

    status_code = 0
}
