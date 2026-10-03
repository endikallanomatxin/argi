Holder : Type = (
    .buffer: String
)

Holder init(.allocator: $&Allocator) -> (.result: Holder) := {
    assume allocator

    result.buffer = unwrap_or_abort(.value = String(.allocator = allocator, .capacity = 1))
}

deinit(.self: $&Holder, .allocator: $&Allocator) -> () := {
    assume allocator

    deinit(.self = $&self&.buffer, .allocator = allocator)
}

append(.self: $&Holder, .allocator: $&Allocator) -> () := {
    assume allocator

    _ ::= push_byte(.self = $&self&.buffer, .byte = 65, .allocator = allocator)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    holder ::= Holder(.allocator = $&allocator_storage)
    i :: UIntNative = 0
    while i < 1 {
        append(.self = $&holder, .allocator = $&allocator_storage)
        i = i + 1
    }

    if holder.buffer.length != 1 {
        status_code = 1
        return
    }
    deinit(.self = $&holder, .allocator = $&allocator_storage)
}
