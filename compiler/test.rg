other_function() := {
    c := 2
    return 0
}

main() := {
    -- TODO: Make it mandatory to declare return types in functions

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

    return 0
}
