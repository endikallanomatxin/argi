main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    i :: UIntNative = 0
    while i < 2 {
        local ::= String(.allocator = system.allocator, .capacity = 1)
        pushed ::= push_byte(.self = $&local, .byte = 65, .allocator = system.allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        data ::= local.allocation.data
        if data& != 65 {
            status_code = 2
            return
        }
        deinit(.self = $&local, .allocator = system.allocator)
        i = i + 1
    }
}
