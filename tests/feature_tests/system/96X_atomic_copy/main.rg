run_main(.system: System) -> !Void = ..ok Void() := {
    cell ::= AtomicUInt32(.initial = 1, .ffi = system.ffi)!
    duplicate ::= cell
    store(.self = $&duplicate, .value = 2)
    if load(.self = &cell).value != 1 { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
