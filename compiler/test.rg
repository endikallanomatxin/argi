main := {
    -- Separate declaration and assignment is implemented
    a :: Int
    a = 12

    -- Combined declaration and assignment also works
    b ::= 32

    -- Declaration of a constant from an expression also works
    c := a + b

    return c
}
