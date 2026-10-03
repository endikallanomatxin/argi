semver := import ("semver")
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = format(.value = "1.2.3", .allocator = $&allocator)).result
    version ::= unwrap_or_abort(.value = semver.parse(.text = as_view(.self = &text).view)).result
    deinit(.self = $&text, .allocator = $&allocator)
    major ::= semver.major(.self = &version).text
    if bytes_get(.view = &major, .index = 0).byte != 49 { abort }
}
