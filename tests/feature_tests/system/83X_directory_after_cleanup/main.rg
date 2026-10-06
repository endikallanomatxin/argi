run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    directory ::= Directory(.self = system.file_system, .path = ".")!
    deinit(.self = $&directory)
    _ ::= next(.self = $&directory)
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
