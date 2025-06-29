add_one (.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

main () -> (.status_code: Int32) := {
    a := 1
    b := add_one(a)

    status_code = b
}
