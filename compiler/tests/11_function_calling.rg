other_function () -> (.status_code: Int32) := {
    a := 1
    return 0
}

main () -> (.status_code: Int32) := {
    b := other_function()

    status_code = b
}
