make(.allocator: $&Allocator) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    assume allocator

    result = allocate(.self = allocator, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    result ::= make(.allocator = $&allocator_storage)
    match result {
        ..error _ {
            status_code = 1
        }
        ..ok ~ payload {
            allocation ::= ~payload
            duplicate ::= ~payload
            deinit(.self = $&allocation)
            deinit(.self = $&duplicate)
            status_code = 0
        }
    }
}
