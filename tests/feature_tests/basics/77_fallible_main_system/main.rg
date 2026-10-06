run_main(.system: System) -> !Void = ..ok Void() := {
    write(.self = $&system.terminal&.stdout, .text = "ready\n")!
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
