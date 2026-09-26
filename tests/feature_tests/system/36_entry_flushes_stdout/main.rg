main(.system: System) -> (.status_code: Int32 = 0) := {
    write_byte(.self = system.terminal&.stdout_writer, .byte = 65)
}
