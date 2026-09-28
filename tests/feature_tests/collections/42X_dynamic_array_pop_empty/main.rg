main (.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    values :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&values)

    pop_result ::= pop(.self = $&values).result
    if is(.value = pop_result, .variant = ..error) {
        if is(.value = pop_result..error.reason, .variant = ..empty) {
            status_code = 0
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
