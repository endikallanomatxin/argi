main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 1)!!!
    parts ::= split("a,b", .separator = view(&text))!!!
    deinit(.self = $&text)

    for part in parts {
        if part == "a" { abort }
    }
    status_code = 0
}
