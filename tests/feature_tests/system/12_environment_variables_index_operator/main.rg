main(.system: System = System()) -> (.status_code: Int32) := {
    home_literal ::= from_literal(.data = "HOME")
    missing_literal ::= from_literal(.data = "ARGI_ENV_SHOULD_NOT_EXIST_476")
    home_key ::= as_view(.self = home_literal)
    missing_key ::= as_view(.self = missing_literal)

    home_result ::= system.env_vars[home_key]
    if is(.value = home_result, .variant = ..error) {
        status_code = 4
        return
    }
    home ::= home_result..ok
    if home? {
        if home.length < 1 {
            status_code = 2
            return
        }
    } else {
        status_code = 1
        return
    }

    missing_result ::= system.env_vars[missing_key]
    if is(.value = missing_result, .variant = ..error) {
        status_code = 5
        return
    }
    missing ::= missing_result..ok
    if missing? {
        status_code = 3
        return
    }

    status_code = 0
}
