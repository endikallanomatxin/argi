main(.system: System) -> (.status_code: Int32) := {
    allocator ::= system.allocator
    text ::= String(.length = 1)
    bytes_set(.string = $&text, .index = 0, .value = 65)

    if bytes_get(.string = &text, .index = 0).byte != 65 {
        status_code = 1
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
