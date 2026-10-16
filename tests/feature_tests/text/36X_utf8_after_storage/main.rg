run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    text ::= format(.value = "hello", .allocator = allocator)!
    validated ::= CodepointView(.text = view(.self = &text))
    iterator ::= to_iterator(.value = &validated).iterator
    deinit(.self = $&text)
    next(.self = $&iterator)
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
