main() -> (.status_code: Int32) := {
    allocator :: PageAllocator = PageAllocator()

    if allocator.page_size == 0 {
        status_code = 10
        return
    }

    first_result ::= allocate(.self = $&allocator, .size = 1)
    match first_result {
    ..error _ { status_code = 14 }
    ..ok ~ first_payload {
    first ::= ~first_payload
    second_result ::= allocate(.self = $&allocator, .size = allocator.page_size + 1)
    match second_result {
    ..error _ { status_code = 15 }
    ..ok ~ second_payload {
    second ::= ~second_payload

    first_addr :: UIntNative = cast#(.to: UIntNative)(.value = first.data)
    second_addr :: UIntNative = cast#(.to: UIntNative)(.value = second.data)

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

    deinit(.self = $&first)
    deinit(.self = $&second)
    status_code = 0
    }
    }
    }
    }
}
