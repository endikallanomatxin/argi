main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= format(.value = "hello", .allocator = allocator)!
    validated ::= Utf8View(.text = as_view(.self = &text))!
    iterator ::= to_iterator(.value = &validated).iterator
    deinit(.self = $&text, .allocator = allocator)
    next(.self = $&iterator)
}
