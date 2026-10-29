main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stdout

    print(.value = "literal output")
}
