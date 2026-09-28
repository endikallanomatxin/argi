main(.system: System) -> (.status_code: Int32) := {
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    attempt ::= allocate(.self = $&allocator, .size = 1, .alignment = 3)
    status_code = 0
}
