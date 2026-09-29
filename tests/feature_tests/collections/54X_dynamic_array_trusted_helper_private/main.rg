main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    #defer deinit(.self = $&array, .allocator = $&allocator_storage)
    value ::= _trusted_dynamic_array_get#(.t: Int32)(.array = &array, .index = 0)
    status_code = value
}
