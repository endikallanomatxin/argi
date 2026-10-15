run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 1)!
    borrowed ::= &array
    for ~item in borrowed {}
}

main#(.WriterType: Type: Writer#(WriterType))(.system: System, .writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
