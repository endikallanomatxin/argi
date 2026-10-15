run_main(.system: System) -> !Void = ..ok Void() := {
    write(.self = $&system.terminal&.stdout, .value = "ready\n")!
}

main#(.WriterType: Type: Writer#(WriterType))(.system: System, .writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
