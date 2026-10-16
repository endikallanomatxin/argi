run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: String, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!
    text ::= format(.value = "owned", .allocator = allocator)!
    put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!
    query :: Int32 = 1
    view(.self = &text)
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
