main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    owner ::= TemporaryDirectory(.self = system.file_system, .parent = ".")!!!
    _ ::= owner._handle
    status_code = 0
}
