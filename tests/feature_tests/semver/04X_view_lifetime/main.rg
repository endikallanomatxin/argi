semver := import ("semver")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = format(.value = "1.2.3", .allocator = $&allocator)).result
    version ::= unwrap_or_abort(.value = semver.parse(.text = view(.self = &text).view)).result
    deinit(.self = $&text)
    major ::= semver.major(.self = &version).text
    if unwrap_or_abort(.value = bytes_get(.view = &major, .index = 0)) != 49 { abort }
}
