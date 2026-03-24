main() -> (.status_code: Int32) := {
    file ::= File(.handle = 0, .kind = ..other, .should_close = 0 == 1)
    open_write(.p = $&file, .path = "/dev/null")

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
