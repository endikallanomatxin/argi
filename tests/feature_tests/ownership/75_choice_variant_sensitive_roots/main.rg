make(.allocator: $&Allocator, .condition: Bool) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    assume allocator

    if condition {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = allocate(.self = allocator, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    failed ::= make(.allocator = $&allocator_storage, .condition = true)
    match failed {
        ..error _ {
            status_code = 0
        }
        ..ok ~ payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 1
        }
    }

    succeeded ::= make(.allocator = $&allocator_storage, .condition = false)
    match succeeded {
        ..error _ {
            status_code = 2
        }
        ..ok ~ payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
        }
    }
}
