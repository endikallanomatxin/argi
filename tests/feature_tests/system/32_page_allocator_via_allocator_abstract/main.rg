alloc_one(
    .allocator: $&Allocator,
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            allocation ::= ~payload
            result = ..ok cast#(.to: UIntNative)(.value = allocation.data)
            deinit(.self = $&allocation)
        }
    }
}

main() -> (.status_code: Int32) := {
    allocator :: PageAllocator = PageAllocator()
    allocated ::= alloc_one(.allocator = $&allocator)
    if is(.value = allocated, .variant = ..error) {
        status_code = 2
        return
    }
    addr ::= allocated..ok

    if addr == 0 {
        status_code = 1
        return
    }

    status_code = 0
}
