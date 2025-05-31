other_function() := {
    c := 2
    return 0
}

main() := {
    -- Separate declaration and assignment is implemented
    a :: Float
    a = 12
    a = 0x10
    a = 0o10
    a = 0b10

    -- Combined declaration and assignment also works
    b ::= 32.0
    b = 1e10

    -- Declaration of a constant from an expression also works
    c := a + b


    -- TODO: Allow function calling
    -- d := other_function()

    return 0
}
