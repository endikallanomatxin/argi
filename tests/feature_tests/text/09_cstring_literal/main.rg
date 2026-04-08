main() -> (.status_code: Int32) := {
    c_text ::= from_literal(.data = "OK")
    if strlen(.string = c_text).length != 2 {
        status_code = 1
        return
    }

    status_code = 0
}
