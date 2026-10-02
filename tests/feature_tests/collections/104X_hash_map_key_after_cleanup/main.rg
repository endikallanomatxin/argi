main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: StringView, .value: Int32, .policy: StringViewHashPolicy)(.policy = StringViewHashPolicy(), .allocator = allocator))
    source ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    bytes_set(.string = $&source, .index = 0, .value = 97)
    unwrap_or_abort(.value = put(.self = $&map, .key = as_view(.self = &source).view, .value = 1, .allocator = allocator))
    deinit(.self = $&source, .allocator = allocator)
    if contains(.self = &map, .key = "a").ok == false { abort }
    deinit(.self = $&map, .allocator = allocator)
}
