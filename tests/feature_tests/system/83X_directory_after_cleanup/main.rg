main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    directory ::= Directory(.self = system.file_system, .path = ".")!!!
    deinit(.self = $&directory)
    _ ::= next(.self = $&directory)
    status_code = 0
}
