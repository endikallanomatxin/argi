main(.system: System = System()) -> (.status_code: Int32) := {
    key_literal ::= from_literal(.data = "PATH")
    key ::= as_view(.self = key_literal)

    found ::= get(.self = system.env_vars, .key = key)
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
