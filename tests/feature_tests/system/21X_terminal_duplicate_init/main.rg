main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator ::= $&allocator_storage
    assume allocator
    second := Terminal()
    status_code = 0
}
