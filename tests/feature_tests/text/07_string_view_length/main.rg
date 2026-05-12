main(.system: System) -> (.status_code: Int32) := {
    text ::= String(.length = 2)
    bytes_set(.string = $&text, .index = 0, .value = 79)
    bytes_set(.string = $&text, .index = 1, .value = 75)

    view ::= as_view(.self = &text)
    if view.length != 2 {
        status_code = 1
        return
    }

    if bytes_get(.view = &view, .index = 0).byte != 79 {
        status_code = 2
        return
    }

    if bytes_get(.view = &view, .index = 1).byte != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
