alloc_one(
    .allocator: $&Allocator,
) -> (.value: UIntNative) := {
    ptr ::= allocate(.self = allocator, .size = 1)
    value = cast#(.to: UIntNative)(.value = ptr)
    deallocate(.self = allocator, .data = ptr, .size = 1)
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
