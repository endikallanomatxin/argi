main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout, .buffer = view(.self = $&zeroed#(.t: [4]UInt8)())
    )
    unwrap_or_abort(.value = print("Buffered output"))
    -- The pending tail is written by scope cleanup.
    unwrap_or_abort(.value = Writer#().write_byte(.self = writer, .byte = 79))
    unwrap_or_abort(.value = Writer#().write_byte(.self = writer, .byte = 75))
}
