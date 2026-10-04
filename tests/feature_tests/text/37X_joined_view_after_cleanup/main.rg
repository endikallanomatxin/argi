main(.system: System) -> (.status_code: Int32 = 0) := {
    parts: [1]StringView = ("a")
    text ::= unwrap_or_abort(
        .value = join(
            .parts     = array_view_ro(.array = &parts).view
            .separator = ""
            .allocator = system.page_allocator
        )
    )
    view ::= as_view(.self = &text).view
    deinit(.self = $&text, .allocator = system.page_allocator)
    observed ::= view.data&
}
