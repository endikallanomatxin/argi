Borrow := (.first: &Int32, .second: &Int32)

bad := (.stable: &Int32) -> (.result: &Int32) {
    local: Int32 = 41
    refs: Borrow = (.second = &local, .first = stable)
    result = refs.second
}

main := () -> (.status_code: Int32 = 0) {
    stable: Int32 = 7
    stale ::= bad(.stable = &stable)
    status_code = stale&
}
