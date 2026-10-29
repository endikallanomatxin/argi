main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    text ::= unwrap_or_abort(
        .value = replace(
            .self = "a", .pattern = "a", .replacement = "b", .allocator = system.page_allocator
        )
    )
    view ::= view(.self = &text).view
    deinit(.self = $&text)
    observed ::= byte_data(.text = view).reference&
}
