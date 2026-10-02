main(.system: System) -> (.status_code: Int32 = 0) := {
    assume writer ::= $&BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout,
        .buffer = array_view(.array = $&zeroed#(.t: [4]UInt8)()),
    )
    unwrap_or_abort(.value = print("Buffered output\n"))
    -- The pending tail is written by scope cleanup.
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 79))
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 75))
}
