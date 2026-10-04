main(.system: System) -> (.status_code: Int32 = 0) := {
    text ::= unwrap_or_abort(
        .value = replace(
            .self        = "a"
            .pattern     = "a"
            .replacement = "b"
            .allocator   = system.page_allocator
        )
    )
    view ::= as_view(.self = &text).view
    deinit(.self = $&text, .allocator = system.page_allocator)
    observed ::= view.data&
}
