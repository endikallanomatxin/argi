run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bytes ::= DynamicArray#(.t: UInt8)(.capacity = 2)!
    push(.self = $&bytes, .value = 1)!
    push(.self = $&bytes, .value = 2)!
    reader ::= ByteReader(.bytes = view(.array = &bytes))
    deinit(.self = $&bytes)
    _ ::= read_uint16(.self = $&reader, .order = ..big)!
}

main#(.WriterType: Type: Writer#(WriterType))(.system: System, .writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
