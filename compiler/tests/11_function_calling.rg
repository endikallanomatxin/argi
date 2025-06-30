other_function () -> (.r: Int32) := {
    r = 42
}

main () -> (.status_code: Int32) := {
    status_code = other_function().r
}
