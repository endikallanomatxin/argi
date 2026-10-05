main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 1)!
    parts ::= split("a,b", .separator = as_view(&text))!
    deinit(.self = $&text, .allocator = allocator)

    for part in parts {
        if part == "a" { abort }
    }
}
