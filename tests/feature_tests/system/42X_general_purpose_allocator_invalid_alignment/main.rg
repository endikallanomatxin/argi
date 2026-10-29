main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    attempt ::= allocate_bytes(.self = $&allocator, .size = 1, .alignment = 3)
    status_code = 0
}
