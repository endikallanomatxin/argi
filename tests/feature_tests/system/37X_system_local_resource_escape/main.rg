local_system(.system: System) -> (.result: System) := {
    local_args :: Arguments = system.args&
    local_args.count = 1
    result = system
    result.args = $&local_args
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    invalid ::= local_system(.system = system).result
    if invalid.args&.count != 1 { status_code = 1 }
}
