main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stdout

    text ::= "string view output"
    print(.value = text)
}
