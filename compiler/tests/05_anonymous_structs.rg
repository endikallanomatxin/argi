main () -> (.status_code: Int32) := {
    anonymous_struct_declared_with_explicit_type : (
        .a: Int32
        .b: Float32
    ) = (
        .a = 1
        .b = 2.0
    )

    anonymous_struct_with_default_values : (
        .a: Int32
        .b: Int32 = 0
    ) = (
        .a = 1
    )

    status_code = anonymous_struct_with_default_values.b
}
