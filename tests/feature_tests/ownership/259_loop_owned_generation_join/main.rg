main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.allocator

    buffer ::= String(.allocator = system.allocator, .capacity = 1)
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_byte(.self = $&buffer, .byte = 65, .allocator = system.allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    if buffer.length != 2 {
        status_code = 2
        return
    }
    deinit(.self = $&buffer, .allocator = system.allocator)
}
