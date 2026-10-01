main(.system: System) -> (.status_code: Int32 = 0) := {
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    bytes_set(.string = $&text, .index = 0, .value = 32)
    bytes_set(.string = $&text, .index = 1, .value = 97)
    bytes_set(.string = $&text, .index = 2, .value = 32)
    view ::= as_view(.self = &text).view
    deinit(.self = $&text, .allocator = system.page_allocator)
    observed ::= view.data&
}
