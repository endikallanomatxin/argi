other_function () -> (.r: Int32) := {
    r = 42
}

main () -> (.status_code: Int32) := {
    r := other_function()

    status_code = r
}
