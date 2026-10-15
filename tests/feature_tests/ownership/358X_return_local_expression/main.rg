escape() -> (.result: &Int32) := {
    local :: Int32 = 7
    return &local
}

main() -> () := {
    escaped ::= escape()
}
