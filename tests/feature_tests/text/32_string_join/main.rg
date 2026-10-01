main(.system: System) -> (.status_code: Int32 = 0) := {
    parts : [3]StringView = ("a", "", "b")
    joined ::= unwrap_or_abort(.value = join(.parts = array_view_ro(.array = &parts).view, .separator = "--", .allocator = system.page_allocator))
    if as_view(.self = &joined).view != "a----b" { abort }
    deinit(.self = $&joined, .allocator = system.page_allocator)
    joined_empty_separator ::= unwrap_or_abort(.value = join(.parts = array_view_ro(.array = &parts).view, .separator = "", .allocator = system.page_allocator))
    if as_view(.self = &joined_empty_separator).view != "ab" { abort }
    deinit(.self = $&joined_empty_separator, .allocator = system.page_allocator)
    empty_parts : [0]StringView = ()
    empty ::= unwrap_or_abort(.value = join(.parts = array_view_ro(.array = &empty_parts).view, .separator = ",", .allocator = system.page_allocator))
    if empty.length != 0 { abort }
    deinit(.self = $&empty, .allocator = system.page_allocator)
    source ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    bytes_set(.string = $&source, .index = 0, .value = 97)
    bytes_set(.string = $&source, .index = 1, .value = 0)
    bytes_set(.string = $&source, .index = 2, .value = 98)
    view ::= as_view(.self = &source).view
    aliased : [2]StringView = (view, view)
    independent ::= unwrap_or_abort(.value = join(.parts = array_view_ro(.array = &aliased).view, .separator = view, .allocator = system.page_allocator))
    deinit(.self = $&source, .allocator = system.page_allocator)
    if independent.length != 9 { abort }
    if bytes_get(.string = &independent, .index = 7).byte != 0 { abort }
    if bytes_get(.string = &independent, .index = 8).byte != 98 { abort }
    deinit(.self = $&independent, .allocator = system.page_allocator)
}
