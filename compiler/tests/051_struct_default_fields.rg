main () -> (.status_code: Int32) := {
    anonymous_struct_with_default_values : (
        .a: Int32
        .b: Int32 = 0
    ) = (
        .a = 1
    )

    status_code = anonymous_struct_with_default_values.b
}
