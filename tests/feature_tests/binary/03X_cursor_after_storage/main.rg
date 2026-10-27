main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    bytes ::= DynamicArray#(.t: UInt8)(.capacity = 2)!!!
    push(.self = $&bytes, .value = 1)!!!
    push(.self = $&bytes, .value = 2)!!!
    reader ::= ByteReader(.bytes = view(.self = &bytes))
    deinit(.self = $&bytes)
    _ ::= read_uint16(.self = $&reader, .order = ..big)!!!
    status_code = 0
}
