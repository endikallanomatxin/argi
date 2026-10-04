bad() -> (.result: &Int32) := {
    local :: Int32 = 3
    result = &local
}

main() -> (.status_code: Int32) := {
    stale ::= bad()
    status_code = stale&
}
