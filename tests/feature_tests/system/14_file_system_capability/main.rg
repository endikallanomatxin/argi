main(.system: System = System()) -> (.status_code: Int32) := {
    path ::= from_literal(.data = "/dev/null")

    read_file_result ::= open_read(.self = system.file_sys, .path = path)
    if is(.value = read_file_result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }
    read_file ::= read_file_result..ok.value
    close(.self = $&read_file)

    write_file_result ::= open_write(.self = system.file_sys, .path = path)
    if is(.value = write_file_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    write_file ::= write_file_result..ok.value
    close(.self = $&write_file)

    append_file_result ::= open_append(.self = system.file_sys, .path = path)
    if is(.value = append_file_result, .variant = ..ok) {
    } else {
        status_code = 3
        return
    }
    append_file ::= append_file_result..ok.value
    close(.self = $&append_file)

    status_code = 0
}
