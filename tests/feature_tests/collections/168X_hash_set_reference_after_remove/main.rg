run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    set ::= HashSet#(.key: Int32)()!
    insert($&set, .key = 1)!
    iterator ::= to_reference_iterator(&set).iterator
    key ::= next($&iterator).value
    remove($&set, .key = &1)
    if key&!= 1 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
