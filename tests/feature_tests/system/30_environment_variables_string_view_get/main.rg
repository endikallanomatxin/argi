main(.system: System = System()) -> (.status_code: Int32) := {
    key_literal ::= from_literal(.data = "PATH")
    key ::= as_view(.self = key_literal)

    found_result ::= get(.self = system.env_vars, .key = key)
    if is(.value = found_result, .variant = ..error) {
        status_code = 3
        return
    }
    found ::= found_result..ok
    if found? {
    } else {
        status_code = 1
        return
    }

    payload ::= found..some
    if payload.value.length == 0 {
        status_code = 2
        return
    }

    status_code = 0
}
