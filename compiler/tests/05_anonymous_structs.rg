main () -> (.status_code: Int32) := {
    -- Declaring an anonymous struct with explicit type
    one_struct : (
        .a: Int32
        .b: Int32
    ) = (
        .a = 1
        .b = 2
    )

    -- Declaring an anonymous struct from a literal through type inference
    another_struct := (
        .a := 1
        .b := 2
    )

    status_code = 0
    return status_code
}
