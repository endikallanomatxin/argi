main(.system: System = System()) -> (.status_code: Int32) := {
    home_literal ::= from_literal(.data = "HOME")
    path_literal ::= from_literal(.data = "PATH")
    missing_literal ::= from_literal(.data = "ARGI_ENV_SHOULD_NOT_EXIST_475")
    home_key ::= as_view(.self = home_literal)
    path_key ::= as_view(.self = path_literal)
    missing_key ::= as_view(.self = missing_literal)

    if has(.self = system.env_vars, .key = home_key).ok {
    } else {
        status_code = 1
        return
    }

    if has(.self = system.env_vars, .key = path_key).ok {
    } else {
        status_code = 2
        return
    }

    home ::= get(.self = system.env_vars, .key = home_key)
    if home? {
        if home.length < 1 {
            status_code = 4
            return
        }
    } else {
        status_code = 3
        return
    }

    missing ::= get(.self = system.env_vars, .key = missing_key)
    if missing? {
        status_code = 5
        return
    }

    status_code = 0
}
