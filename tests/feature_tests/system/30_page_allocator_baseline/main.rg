main() -> (.status_code: Int32) := {
    allocator_storage :: PageAllocator = PageAllocator()
    assume allocator ::= $&allocator_storage

    if allocator_storage.page_size == 0 {
        status_code = 10
        return
    }

    first_result ::= allocate(.self = $&allocator_storage, .size = 1, .alignment = allocator_storage.page_size)
    match first_result {
    ..error _ { status_code = 14 }
    ..ok ~ first_payload {
    first ::= ~first_payload
    second_result ::= allocate(.self = $&allocator_storage, .size = allocator_storage.page_size + 1)
    match second_result {
    ..error _ { status_code = 15 }
    ..ok ~ second_payload {
    second ::= ~second_payload

    first_addr :: UIntNative = first.data.address
    second_addr :: UIntNative = second.data.address

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

    if first_addr % allocator_storage.page_size != 0 or second_addr % allocator_storage.page_size != 0 {
        status_code = 16
        return
    }

    if first.size != 1 or second.size != allocator_storage.page_size + 1 {
        status_code = 17
        return
    }

    deinit(.self = $&first)
    deinit(.self = $&second)
    high_alignment ::= allocator_storage.page_size * 4
    over_aligned_result ::= allocate(.self = $&allocator_storage, .size = 5, .alignment = high_alignment)
    match over_aligned_result {
        ..error _ { status_code = 18
            return }
        ..ok ~ payload {
            over_aligned ::= ~payload
            if over_aligned.data.address % high_alignment != 0 {
                status_code = 19
                return
            }
            deinit(.self = $&over_aligned)
        }
    }
    status_code = 0
    }
    }
    }
    }
}
