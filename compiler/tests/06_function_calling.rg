other_function () -> (Int32) := {
    a := 1
    return 0
}

main () -> (Int32) := {
    b := other_function()
    return b
}
