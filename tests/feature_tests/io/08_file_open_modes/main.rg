main() -> (.status_code: Int32) := {
    path ::= from_literal(.data = "/dev/null")

    read_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    read_result ::= open_read(.p = $&read_file, .path = path)
    if is(.value = read_result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }
    close(.self = $&read_file)

    write_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    write_result ::= open_write(.p = $&write_file, .path = path)
    if is(.value = write_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    close(.self = $&write_file)

    append_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    append_result ::= open_append(.p = $&append_file, .path = path)
    if is(.value = append_result, .variant = ..ok) {
    } else {
        status_code = 3
        return
    }
    close(.self = $&append_file)

    status_code = 0
}
