main(.system: System) -> (.status_code: Int32 = 0) := {
    separator ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 1))
    bytes_set(.string = $&separator, .index = 0, .value = 44)
    iterator ::= unwrap_or_abort(.value = split(.self = "a,b", .separator = as_view(.self = &separator).view))
    deinit(.self = $&separator, .allocator = system.page_allocator)
    segment ::= next(.self = $&iterator).value
    if segment == "a" { abort }
}
