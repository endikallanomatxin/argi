helper(.allocator: $&Allocator) -> (.ok: Bool) := {
    text ::= String(.allocator = allocator, .capacity = 1)
    #defer deinit(.self = $&text, .allocator = allocator)

    if push_byte_growing(.self = $&text, .byte = 65, .allocator = allocator).ok {
    } else {
        ok = false
        return
    }

    if text.length != 1 {
        ok = false
        return
    }

    ok = true
}

main(.system: System = System()) -> (.status_code: Int32) := {
    if helper(.allocator = system.allocator).ok {
        status_code = 0
    } else {
        status_code = 1
    }
}
