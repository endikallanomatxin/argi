run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 1)!
    parts ::= split("a,b", .separator = as_view(&text))!
    deinit(.self = $&text, .allocator = allocator)

    for part in parts {
        if part == "a" { abort }
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
