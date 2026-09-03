main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    buffer ::= String(.allocator = system.allocator, .capacity = 1)
    first ::= push_byte(.self = $&buffer, .byte = 65, .allocator = system.allocator)
    if is(.value = first, .variant = ..error) {
        return
    }
    i :: UIntNative = 0
    while i < 1 {
        pushed ::= push_byte(.self = $&buffer, .byte = 66, .allocator = system.allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    fresh_data ::= buffer.allocation.data
    if fresh_data& != 65 {
        status_code = 2
        return
    }
    deinit(.self = $&buffer, .allocator = system.allocator)
}
