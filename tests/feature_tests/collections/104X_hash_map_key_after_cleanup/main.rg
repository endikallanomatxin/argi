main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= system.page_allocator
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: StringView, .value: Int32, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy(), .allocator = allocator
        )
    )
    source ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 0, .byte = 97))
    unwrap_or_abort(
        .value = put(
            .self = $&map, .key = view(.self = &source).view, .value = 1, .allocator = allocator
        )
    )
    deinit(.self = $&source)
    if contains(.self = &map, .key = "a").ok == false { abort }
    deinit(.self = $&map)
}
