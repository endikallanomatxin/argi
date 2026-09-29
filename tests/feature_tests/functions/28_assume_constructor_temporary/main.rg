make#(.t: Type)(.system: System) -> (.result: t) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = String(.capacity = 8))
    result = 7
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    text ::= unwrap_or_abort(.value = String(.capacity = 8))
    if text.length != 0 { status_code = 1 }
    if make#(.t: Int32)(.system = system).result != 7 { status_code = 2 }
}
