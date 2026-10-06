run_main(.system: System) -> !Void = ..ok Void() := {
    directory ::= Directory(.self = system.file_system, .path = ".")!
    copy ::= directory
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
