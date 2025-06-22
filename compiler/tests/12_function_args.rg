add_one (.a: Int32) -> (.result: Int32) := {
    return a + 1
}

main () -> (.status_code: Int32) := {
    a := 1
    b := add_one(a)

    status_code = b
}
