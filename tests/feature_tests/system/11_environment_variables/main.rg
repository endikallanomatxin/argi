main(.system: System = System()) -> (.status_code: Int32) := {
    home_literal ::= from_literal(.data = "HOME")
    path_literal ::= from_literal(.data = "PATH")
    missing_literal ::= from_literal(.data = "ARGI_ENV_SHOULD_NOT_EXIST_475")
    home_key ::= as_view(.self = home_literal)
    path_key ::= as_view(.self = path_literal)
    missing_key ::= as_view(.self = missing_literal)

    home_has ::= has(.self = system.env_vars, .key = home_key)
    if is(.value = home_has, .variant = ..ok) and home_has..ok {
    } else {
        status_code = 1
        return
    }

    path_has ::= has(.self = system.env_vars, .key = path_key)
    if is(.value = path_has, .variant = ..ok) and path_has..ok {
    } else {
        status_code = 2
        return
    }

    home_result ::= get(.self = system.env_vars, .key = home_key)
    if is(.value = home_result, .variant = ..error) {
        status_code = 6
        return
    }
    home ::= home_result..ok
    if home? {
        if home.length < 1 {
            status_code = 4
            return
        }
    } else {
        status_code = 3
        return
    }

    missing_result ::= get(.self = system.env_vars, .key = missing_key)
    if is(.value = missing_result, .variant = ..error) {
        status_code = 7
        return
    }
    missing ::= missing_result..ok
    if missing? {
        status_code = 5
        return
    }

    status_code = 0
}
