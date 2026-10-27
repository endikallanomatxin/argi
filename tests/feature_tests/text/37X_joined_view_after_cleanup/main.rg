main := (.system: System) -> (.status_code: Int32 = 0) {
    parts: [1]StringView = ("a")
    text ::= unwrap_or_abort(
        .value = join(
            .parts = view(.self = &parts), .separator = "", .allocator = system.page_allocator
        )
    )
    borrowed_view ::= view(.self = &text).view
    deinit(.self = $&text)
    observed ::= byte_data(.text = borrowed_view).reference&
}
