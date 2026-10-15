main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 1)
    )
    i :: UIntNative = 0
    while i < 2 {
        pushed ::= push_ascii(.self = $&buffer, .byte = 65, .allocator = $&allocator_storage)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    if byte_length(&buffer).count != 2 {
        status_code = 2
        return
    }
    deinit(.self = $&buffer)
}
