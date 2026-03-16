add_one (.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

double (.i: Int32) -> (.o: Int32) := {
    o = i * 2
}

main () -> (.status_code: Int32) := {
    status_code = 20 | add_one(.i = _) | double(.i = _)
}
