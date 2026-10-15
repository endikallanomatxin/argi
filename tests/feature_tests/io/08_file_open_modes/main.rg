main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    #if target_os("windows") {
        path ::= from_literal(.data = "NUL")
    } #else {
        path ::= from_literal(.data = "/dev/null")
    }

    read_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    read_result ::= open(.p = $&read_file, .path = path, .mode = ..read)
    if is(.value = read_result, .variant = ..ok) {
    } else {
        status_code = 1
        return
    }
    close(.self = $&read_file)

    write_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    write_result ::= open(.p = $&write_file, .path = path, .mode = ..write)
    if is(.value = write_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    close(.self = $&write_file)

    append_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    append_result ::= open(.p = $&append_file, .path = path, .mode = ..append)
    if is(.value = append_result, .variant = ..ok) {
    } else {
        status_code = 3
        return
    }
    close(.self = $&append_file)

    status_code = 0
}
