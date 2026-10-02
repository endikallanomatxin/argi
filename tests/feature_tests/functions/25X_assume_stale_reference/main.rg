read(.reference: $&Allocation) -> (.result: UIntNative) := {
    result = reference&.size
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            assume reference ::= $&allocation
            deinit(.self = $&allocation)
            observed ::= read()
        }
    }
}
