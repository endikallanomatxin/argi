Holder : Type = (
    .buffer: String
)

init(.p: $&Holder, .allocator: $&Allocator) -> () := {
    p&.buffer = String(.allocator = allocator, .capacity = 1)
}

deinit(.self: $&Holder, .allocator: $&Allocator) -> () := {
    deinit(.self = $&self&.buffer, .allocator = allocator)
}

append(.self: $&Holder, .allocator: $&Allocator) -> () := {
    _ ::= push_byte(.self = $&self&.buffer, .byte = 65, .allocator = allocator)
}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    holder ::= Holder(.allocator = system.allocator)
    i :: UIntNative = 0
    while i < 1 {
        append(.self = $&holder, .allocator = system.allocator)
        i = i + 1
    }

    if holder.buffer.length != 1 {
        status_code = 1
        return
    }
    deinit(.self = $&holder, .allocator = system.allocator)
}
