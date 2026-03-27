main(.system: System) -> (.status_code: Int32) := {
    text ::= String(.length = 3)
    bytes_set(.string = $&text, .index = 0, .value = 65)
    bytes_set(.string = $&text, .index = 1, .value = 114)
    bytes_set(.string = $&text, .index = 2, .value = 103)

    nul ::= bytes_get(.string = &text, .index = 3).byte
    if nul != 0 {
        status_code = 1
        return
    }

    view ::= as_view(.self = &text)
    if bytes_get(.view = &view, .index = 0).byte != 65 {
        status_code = 2
        return
    }

    c_text ::= as_c_string(.self = &text)
    c_ptr ::= pointer(.self = &c_text)
    if strlen(.string = c_ptr).length != 3 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
