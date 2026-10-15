recurse(.n: Int32) -> (.result: &Int32) := {
    local ::= n
    if n == 0 { result = &local } else { result = recurse(.n = n - 1) }
}

main() -> (.status_code: Int32 = 0) := {
    reference ::= recurse(.n = 2)
    status_code = reference&
}
