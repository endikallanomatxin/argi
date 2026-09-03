make(.allocator: $&Allocator, .condition: Bool) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    if condition {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    result = allocate(.self = allocator, .size = 1)
}

main(.system: System) -> (.status_code: Int32) := {
    failed ::= make(.allocator = system.allocator, .condition = true)
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

    succeeded ::= make(.allocator = system.allocator, .condition = false)
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
