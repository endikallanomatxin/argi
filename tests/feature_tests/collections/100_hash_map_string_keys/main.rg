main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(.value = HashMap#(.key: StringView, .value: Int32, .policy: StringViewHashPolicy)(.policy = StringViewHashPolicy(), .allocator = allocator))
    source ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    bytes_set(.string = $&source, .index = 0, .value = 97)
    unwrap_or_abort(.value = put(.self = $&map, .key = as_view(.self = &source).view, .value = 1, .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = "b", .value = 2, .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = "c", .value = 3, .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = "d", .value = 4, .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = "e", .value = 5, .allocator = allocator))
    unwrap_or_abort(.value = put(.self = $&map, .key = "a", .value = 9, .allocator = allocator))
    if length(.self = &map).count != 5 { abort }
    match get(.self = &map, .key = "a").result {
        ..none { abort }
        ..some entry { if entry.value != 9 { abort } }
    }
    deinit(.self = $&map, .allocator = allocator)
    deinit(.self = $&source, .allocator = allocator)
}
