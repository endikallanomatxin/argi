run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    owner ::= TemporaryDirectory(.self = system.file_system, .parent = ".")!
    _ ::= owner._handle
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
