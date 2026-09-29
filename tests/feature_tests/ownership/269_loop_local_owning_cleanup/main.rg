unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    i :: UIntNative = 0
    while i < 2 {
        local ::= unwrap_or_abort(.value = String(.allocator = $&allocator_storage, .capacity = 1))
        pushed ::= push_byte(.self = $&local, .byte = 65, .allocator = $&allocator_storage)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        data ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&local.allocation, .offset = 0).reference
        if data& != 65 {
            status_code = 2
            return
        }
        deinit(.self = $&local, .allocator = $&allocator_storage)
        i = i + 1
    }
}
