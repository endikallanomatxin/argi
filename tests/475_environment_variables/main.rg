main(.system: System = System()) -> (.status_code: Int32) := {
    home_key ::= from_literal(.data = "HOME")
    path_key ::= from_literal(.data = "PATH")
    missing_key ::= from_literal(.data = "ARGI_ENV_SHOULD_NOT_EXIST_475")

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
    if is(.value = home, .variant = ..some) {
    } else {
        status_code = 3
        return
    }

    home_value ::= home..some
    if home_value.value.length < 1 {
        status_code = 4
        return
    }

    missing ::= get(.self = system.env_vars, .key = missing_key)
    if is(.value = missing, .variant = ..none) {
    } else {
        status_code = 5
        return
    }

    status_code = 0
}
