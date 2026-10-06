global :: Int32 = 17

read() -> (.result: &Int32) := {
    result = &global
}

main() -> (.status_code: Int32 = 0) := {
    reference ::= read()
    if reference&!= 17 { status_code = 1 }
}
