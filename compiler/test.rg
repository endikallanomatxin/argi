main := {
    -- Separate declaration and assignment is implemented
    a :: Float
    a = 12

    -- Combined declaration and assignment also works
    b ::= 32.0

    -- Declaration of a constant from an expression also works
    c := a + b

    return 0
}
