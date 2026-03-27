main () -> (.status_code: Int32) := {
    anonymous_struct :: (.a: Int32) = (.a = 1)

    anonymous_struct.a = 0

    status_code = anonymous_struct.a
}
