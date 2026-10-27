main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    directory ::= Directory(.self = system.file_system, .path = ".")!!!
    copy ::= directory
    status_code = 0
}
