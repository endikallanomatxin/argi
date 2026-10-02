main (.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    values :: DynamicArray#(.t: Int32) = unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    #defer deinit(.self = $&values)

    index :: UIntNative = 0
    set_result ::= set(.self = $&values, .index = index, .value = 42, .allocator = $&allocator_storage).result
    if is(.value = set_result, .variant = ..error) {
        if is(.value = set_result..error.reason, .variant = ..out_of_bounds) {
            status_code = 0
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
