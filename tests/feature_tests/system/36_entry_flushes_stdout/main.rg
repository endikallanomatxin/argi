main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    Writer#().write_byte(.self = $&system.terminal&.stdout, .byte = 65)
}
