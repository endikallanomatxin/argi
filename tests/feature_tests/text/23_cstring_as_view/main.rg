main() -> (.status_code: Int32) := {
    c_text ::= from_literal(.data = "hello")
    view ::= as_view(.self = c_text)

    if view.length != 5 {
        status_code = 1
        return
    }

    if bytes_get(.view = &view, .index = 0).byte != 104 {
        status_code = 2
        return
    }

    if bytes_get(.view = &view, .index = 4).byte != 111 {
        status_code = 3
        return
    }

    status_code = 0
}
