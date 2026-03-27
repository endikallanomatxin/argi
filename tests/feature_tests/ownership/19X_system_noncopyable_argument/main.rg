consume(.system: System) -> (.status_code: Int32) := {
    status_code = 0
}

main(.system: System = System()) -> (.status_code: Int32) := {
    status_code = consume(.system = system)
}
