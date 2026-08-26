alloc_one(
    .allocator: $&Allocator,
) -> (.value: UIntNative) := {
    allocation ::= allocate(.self = allocator, .size = 1)
    value = cast#(.to: UIntNative)(.value = allocation.data)
    deinit(.self = $&allocation)
}

main() -> (.status_code: Int32) := {
    allocator :: PageAllocator = PageAllocator()
    addr ::= alloc_one(.allocator = $&allocator).value

    if addr == 0 {
        status_code = 1
        return
    }

    status_code = 0
}
