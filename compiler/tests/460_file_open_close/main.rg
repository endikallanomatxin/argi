main() -> (.status_code: Int32) := {
    file ::= File(.handle = 0, .should_close = 0 == 1)
    path ::= from_literal(.data = "/dev/null")
    open(.p = $&file, .path = path, .mode = ..write)

    if is_open(.self = &file).ok {
    } else {
        status_code = 1
        return
    }

    write_byte(.self = $&file, .byte = 65)
    flush(.self = $&file)
    close(.self = $&file)

    if is_open(.self = &file).ok {
        status_code = 2
        return
    }

    status_code = 0
}
