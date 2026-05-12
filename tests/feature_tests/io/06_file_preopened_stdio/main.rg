main(.system: System = System()) -> (.status_code: Int32) := {
    stdin_file ::= system.terminal&.stdin_file
    stdout_file ::= system.terminal&.stdout_file
    stderr_file ::= system.terminal&.stderr_file

    if is_open(.self = &stdin_file).ok {
    } else {
        status_code = 1
        return
    }

    if is_open(.self = &stdout_file).ok {
    } else {
        status_code = 2
        return
    }

    if is_open(.self = &stderr_file).ok {
    } else {
        status_code = 3
        return
    }

    status_code = 0
}
