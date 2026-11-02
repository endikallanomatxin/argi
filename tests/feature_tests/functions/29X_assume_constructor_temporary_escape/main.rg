bad := (.system: System) -> (.result: $&GeneralPurposeAllocator) {

    allocator_concrete := $&GeneralPurposeAllocator(.allocator = system.page_allocator)

    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)

    assume allocator := virtual_allocator
    result = allocator
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    allocator ::= bad(.system = system).result
}
