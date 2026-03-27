main() -> (.status_code: Int32) := {
    path ::= from_literal(.data = "/dev/null")

    read_file ::= File(.handle = 0, .should_close = 0 == 1)
    open_read(.p = $&read_file, .path = path)
    if is_open(.self = &read_file).ok {
    } else {
        status_code = 1
        return
    }
    close(.self = $&read_file)

    write_file ::= File(.handle = 0, .should_close = 0 == 1)
    open_write(.p = $&write_file, .path = path)
    if is_open(.self = &write_file).ok {
    } else {
        status_code = 2
        return
    }
    close(.self = $&write_file)

    append_file ::= File(.handle = 0, .should_close = 0 == 1)
    open_append(.p = $&append_file, .path = path)
    if is_open(.self = &append_file).ok {
    } else {
        status_code = 3
        return
    }
    close(.self = $&append_file)

    status_code = 0
}
