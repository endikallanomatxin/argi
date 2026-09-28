main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= String(.allocator = $&allocator_storage, .capacity = 1)
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_byte(.self = $&buffer, .byte = 65, .allocator = $&allocator_storage)
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
    deinit(.self = $&buffer, .allocator = $&allocator_storage)
}
