other_function() -> Int32 := {
    c := 2
    return 0
}

main() -> Int32 := {
    -- Separate declaration and assignment is implemented
    a :: Float32
    a = 12
    a = 0x10
    a = 0o10
    a = 0b10

    -- Combined declaration and assignment also works
    b ::= 32.0
    b = 1e10

    -- Declaration of a constant from an expression also works
    c := a + b

    d := other_function()
    if (d != 0) {
        return d
    }

    return 0
}
