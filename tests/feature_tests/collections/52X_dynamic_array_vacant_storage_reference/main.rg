main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    vacant ::= trusted_dynamic_array_storage_pointer#(.t: Int32)(.array = $&array, .offset = 0).pointer
    status_code = vacant&
}
