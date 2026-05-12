main() -> (.status_code: Int32) := {
    allocator :: PageAllocator = PageAllocator()

    if allocator.page_size == 0 {
        status_code = 10
        return
    }

    first ::= allocate(.self = $&allocator, .size = 1)
    second ::= allocate(.self = $&allocator, .size = allocator.page_size + 1)

    first_addr :: UIntNative = cast#(.to: UIntNative)(.value = first)
    second_addr :: UIntNative = cast#(.to: UIntNative)(.value = second)

    if first_addr == 0 {
        status_code = 11
        return
    }

    if second_addr == 0 {
        status_code = 12
        return
    }

    if first_addr == second_addr {
        status_code = 13
        return
    }

    deallocate(.self = $&allocator, .data = first, .size = 1)
    deallocate(.self = $&allocator, .data = second, .size = allocator.page_size + 1)
    status_code = 0
}
