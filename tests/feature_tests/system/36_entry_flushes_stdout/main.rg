main := (.system: System) -> (.status_code: Int32 = 0) {
    Writer<>.write_byte(.self = $&system.terminal&.stdout, .byte = 65)
}
