main (.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    array._length = 100
    status_code = 0
}
