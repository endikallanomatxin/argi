main() -> (.status_code: Int32) := {
    c_text ::= from_literal(.data = "OK")
    c_ptr ::= pointer(.self = &c_text)

    if strlen(.string = c_ptr).length != 2 {
        status_code = 1
        return
    }

    status_code = 0
}
