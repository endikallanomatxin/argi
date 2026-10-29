main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    dep := import ("./dep")

    status_code = dep.load(.allocator = $&allocator_storage).status_code
}
