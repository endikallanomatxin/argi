run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= String(.allocator = allocator, .length = 3)!
    parts ::= split(view(&text), .separator = ",")!
    deinit(.self = $&text)

    for part in parts {
        if part == "a" { abort }
    }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
