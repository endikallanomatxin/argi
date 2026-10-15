escape(.system: System) -> (.result: System) := {
    local_clock ::= ~system.clock&
    result = system
    result.clock = $&local_clock
}

main(.system: System) -> () := {
    escaped ::= escape(system)
}
