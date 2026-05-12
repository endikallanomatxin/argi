main () -> (.status_code: Int32) := {
    anonymous_struct_declared_with_explicit_type : (
        .a: Int32
        .b: Float32
    ) = (
        .a = 0
        .b = 2.0
    )

    status_code = anonymous_struct_declared_with_explicit_type.a
}
