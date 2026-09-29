main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: GeneralPurposeAllocator = GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    first_result ::= allocate(.self = $&allocator_storage, .size = 1, .alignment = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            second_result ::= allocate(.self = $&allocator_storage, .size = 32, .alignment = 32)
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    if first.data.address == second.data.address { status_code = 3
                        return }
                    if second.data.address % 32 != 0 { status_code = 4
                        return }
                    third_result ::= allocate(.self = $&allocator_storage, .size = 4097, .alignment = 8192)
                    match third_result {
                        ..error _ { status_code = 5
                            return }
                        ..ok ~ third_payload {
                            third ::= ~third_payload
                            if third.data.address % 8192 != 0 { status_code = 6
                                return }
                            if third.size != 4097 or third.alignment != 8192 { status_code = 7
                                return }
                            deinit(.self = $&third)
                        }
                    }
                    deinit(.self = $&first)
                    deinit(.self = $&second)
                    if has_live_allocations(.self = &allocator_storage).has_live { status_code = 10
                        return }
                    many ::= unwrap_or_abort(.value = DynamicArray#(.t: Allocation)(.allocator = $&allocator_storage, .capacity = 520))
                    i :: UIntNative = 0
                    while i < 520 {
                        next_result ::= allocate(.self = $&allocator_storage, .size = 8, .alignment = 8)
                        match next_result {
                            ..error _ { status_code = 8
                                return }
                            ..ok ~ next_payload {
                                pushed ::= push#(.t: Allocation)(.self = $&many, .allocator = $&allocator_storage, .value = ~next_payload)
                                if is(.value = pushed, .variant = ..error) { status_code = 9
                                    return }
                            }
                        }
                        i = i + 1
                    }
                    if has_live_allocations(.self = &allocator_storage).has_live == false { status_code = 11
                        return }
                    deinit#(.t: Allocation)(.self = $&many, .allocator = $&allocator_storage)
                    if has_live_allocations(.self = &allocator_storage).has_live { status_code = 12
                        return }
                    status_code = 0
                }
            }
        }
    }
}
