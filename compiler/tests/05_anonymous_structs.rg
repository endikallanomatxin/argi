main () -> (.status_code: Int32) := {
    anonymous_struct_declared_with_explicit_type : (
        .a: Int32
        .b: Float32
    ) = (
        .a = 1
        .b = 2.0
    )

    anonymous_struct_declared_with_type_inference := (
        .a := 1
        .b := 2
    )

    -- TODO: This still doesn't work
    anonymous_struct_with_default_values : (
        .a: Int32
        .b: Float32 = 2.0
    ) = (
        .a = 1
    )

    status_code = 0
}
