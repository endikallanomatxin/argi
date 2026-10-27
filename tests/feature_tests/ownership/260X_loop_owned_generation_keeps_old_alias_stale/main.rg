unsafe_allocation := import ("../../_support/unsafe_allocation")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume ffi := system.ffi
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 1)
    )
    first ::= push_ascii(.self = $&buffer, .byte = 65, .allocator = $&allocator_storage)
    if is(.value = first, .variant = ..error) {
        return
    }
    old_data ::= unwrap_or_abort(.value = string_byte_reference(.string = &buffer, .index = 0))
    i :: UIntNative = 0
    while i < 1 {
        pushed ::= push_ascii(.self = $&buffer, .byte = 66, .allocator = $&allocator_storage)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    if old_data&== 65 {
        status_code = 0
    }
}
