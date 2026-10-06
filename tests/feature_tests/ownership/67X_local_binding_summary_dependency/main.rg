identity(.value: &Int32) -> (.out: &Int32) := {
    out = value
}

through_local(.value: &Int32) -> (.out: &Int32) := {
    temporary ::= identity(.value = value)
    out = identity(.value = temporary)
}

bad() -> (.out: &Int32) := {
    local :: Int32 = 7
    out = through_local(.value = &local)
}

main() -> (.status_code: Int32) := {
    stale ::= bad()
    status_code = stale&
}
