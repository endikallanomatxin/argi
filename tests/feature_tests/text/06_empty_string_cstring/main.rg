main(.system: System) -> (.status_code: Int32) := {
    text ::= String(.length = 0)

    if text.length != 0 {
        status_code = 1
        return
    }

    nul ::= bytes_get(.string = &text, .index = 0).byte
    if nul != 0 {
        status_code = 2
        return
    }

    c_text ::= as_c_string(.self = &text)
    c_ptr ::= pointer(.self = &c_text)
    if strlen(.string = c_ptr).length != 0 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
