main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 3)!
    parts ::= split(as_view(&text), .separator = ",")!
    deinit(.self = $&text, .allocator = allocator)

    for part in parts {
        if part == "a" { abort }
    }
}
