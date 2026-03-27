main(.system: System = System()) -> (.status_code: Int32) := {
    home_key ::= from_literal(.data = "HOME")
    missing_key ::= from_literal(.data = "ARGI_ENV_SHOULD_NOT_EXIST_476")

    home ::= system.env_vars[home_key]
    if is(.value = home, .variant = ..some) {
    } else {
        status_code = 1
        return
    }

    home_value ::= home..some
    if home_value.value.length < 1 {
        status_code = 2
        return
    }

    missing ::= system.env_vars[missing_key]
    if is(.value = missing, .variant = ..none) {
    } else {
        status_code = 3
        return
    }

    status_code = 0
}
