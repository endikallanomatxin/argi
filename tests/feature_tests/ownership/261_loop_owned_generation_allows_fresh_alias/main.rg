unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= String(.allocator = $&allocator_storage, .capacity = 1)
    first ::= push_byte(.self = $&buffer, .byte = 65, .allocator = $&allocator_storage)
    if is(.value = first, .variant = ..error) {
        return
    }
    i :: UIntNative = 0
    while i < 1 {
        pushed ::= push_byte(.self = $&buffer, .byte = 66, .allocator = $&allocator_storage)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        i = i + 1
    }

    fresh_data ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&buffer.allocation, .offset = 0).reference
    if fresh_data& != 65 {
        status_code = 2
        return
    }
    deinit(.self = $&buffer, .allocator = $&allocator_storage)
}
