main(.system: System = System()) -> (.status_code: Int32) := {
    home_string ::= String(.length = 4)
    bytes_set(.string = $&home_string, .index = 0, .value = 72)
    bytes_set(.string = $&home_string, .index = 1, .value = 79)
    bytes_set(.string = $&home_string, .index = 2, .value = 77)
    bytes_set(.string = $&home_string, .index = 3, .value = 69)

    home_view ::= as_view(.self = &home_string)

    has_result ::= has(.self = system.env_vars, .key = home_view)
    if is(.value = has_result, .variant = ..ok) and has_result..ok {
    } else {
        status_code = 1
        return
    }

    from_view_result ::= system.env_vars[home_view]
    if is(.value = from_view_result, .variant = ..error) {
        status_code = 3
        return
    }
    from_view ::= from_view_result..ok
    if is(.value = from_view, .variant = ..some) {
    } else {
        status_code = 2
        return
    }

    deinit(.self = $&home_string, .allocator = system.allocator)
    status_code = 0
}
