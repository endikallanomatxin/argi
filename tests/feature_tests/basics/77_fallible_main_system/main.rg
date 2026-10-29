main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    write(.self = $&system.terminal&.stdout, .value = "ready\n")!!!
    status_code = 0
}
