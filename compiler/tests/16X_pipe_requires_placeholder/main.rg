add_one (.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

main () -> (.status_code: Int32) := {
    status_code = 41 | add_one(41)
}
