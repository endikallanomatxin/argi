make() -> (.result: &[2]Int32) := {
    local :: [2]Int32 = (3, 5)
    result = &local
}

main() -> (.status_code: Int32 = 0) := {
    values ::= make()
    if values&[0] != 3 or values&[1] != 5 { status_code = 1 }
}
