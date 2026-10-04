make() -> (.result: &Int32) := {
    local ::= 7
    result = &local
}

main() -> (.status_code: Int32 = 0) := {
    escaped :: &Int32
    {
        reference ::= make()
        escaped = reference
    }
    status_code = escaped&
}
