main(.system: System = System()) -> (.status_code: Int32) := {
    path ::= from_literal(.data = "/dev/null")

    read_file ::= open_read(.self = system.file_sys, .path = path)
    if is_open(.self = &read_file).ok {
    } else {
        status_code = 1
        return
    }
    close(.self = $&read_file)

    write_file ::= open_write(.self = system.file_sys, .path = path)
    if is_open(.self = &write_file).ok {
    } else {
        status_code = 2
        return
    }
    close(.self = $&write_file)

    append_file ::= open_append(.self = system.file_sys, .path = path)
    if is_open(.self = &append_file).ok {
    } else {
        status_code = 3
        return
    }
    close(.self = $&append_file)

    status_code = 0
}
