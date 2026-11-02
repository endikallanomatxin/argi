main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 3)!!!
    parts ::= split(view(&text), .separator = ",")!!!
    deinit(.self = $&text)

    for part in parts {
        if part == "a" { abort }
    }
    status_code = 0
}
