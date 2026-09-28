main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    dep := #import("./dep")

    status_code = dep.load(.allocator = $&allocator_storage).status_code
}
