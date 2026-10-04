make() -> (.result: &Int32) := {
    local ::= 7
    result = &local
}

main() -> (.status_code: Int32 = 0) := {
    i :: Int32 = 0
    while i < 2 {
        reference ::= make()
        status_code = reference&
        i = i + 1
    }
}
