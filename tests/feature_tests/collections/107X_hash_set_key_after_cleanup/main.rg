main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(.value = HashSet#(.key: StringView, .policy: StringViewHashPolicy)(.policy = StringViewHashPolicy(), .allocator = allocator))
    source ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 0, .byte = 97))
    unwrap_or_abort(.value = insert(.self = $&map, .key = as_view(.self = &source).view, .allocator = allocator))
    deinit(.self = $&source)
    if contains(.self = &map, .key = "a").ok == false { abort }
    deinit(.self = $&map)
}
