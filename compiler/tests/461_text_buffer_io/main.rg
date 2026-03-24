main(.system: System = System()) -> (.status_code: Int32) := {
    buffer ::= TextBuffer(.allocator = system.allocator, .capacity = 8)

    push_byte(.self = $&buffer, .byte = 79)
    push_byte(.self = $&buffer, .byte = 75)

    if buffer.length != 2 {
        status_code = 1
        return
    }

    first ::= byte_at(.self = &buffer, .index = 0).byte
    if first != 79 {
        status_code = 2
        return
    }

    second ::= byte_at(.self = &buffer, .index = 1).byte
    if second != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&buffer, .allocator = system.allocator)
    status_code = 0
}
