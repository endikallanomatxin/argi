bad(.system: System) -> (.result: $&GeneralPurposeAllocator) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    result = allocator
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator ::= bad(.system = system).result
}
