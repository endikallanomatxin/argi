main() -> (.status_code: Int32) := {
    allocator_storage :: CAllocator = CAllocator()
    assume allocator ::= $&allocator_storage
    src_result ::= allocate(.self = $&allocator_storage, .size = 4)
    match src_result {
    ..error _ { status_code = 10 }
    ..ok ~ src_payload {
    src_allocation ::= ~src_payload
    dst_result ::= allocate(.self = $&allocator_storage, .size = 4)
    match dst_result {
    ..error _ { status_code = 11 }
    ..ok ~ dst_payload {
    dst_allocation ::= ~dst_payload

    src ::= array_view#(.t: UInt8)(
        .data = src_allocation.data,
        .length = 4,
    )
    dst ::= array_view#(.t: UInt8)(
        .data = dst_allocation.data,
        .length = 4,
    )

    src_set0 ::= set#(.t: UInt8)(.self = $&src, .index = 0, .value = 3).result
    src_set1 ::= set#(.t: UInt8)(.self = $&src, .index = 1, .value = 5).result
    src_set2 ::= set#(.t: UInt8)(.self = $&src, .index = 2, .value = 7).result
    src_set3 ::= set#(.t: UInt8)(.self = $&src, .index = 3, .value = 11).result
    if is(.value = src_set0, .variant = ..error) or is(.value = src_set1, .variant = ..error) or is(.value = src_set2, .variant = ..error) or is(.value = src_set3, .variant = ..error) {
        status_code = 12
        return
    }

    memcpy_bytes(.dst = dst, .src = src)

    dst0 ::= get#(.t: UInt8)(.self = &dst, .index = 0).result
    if is(.value = dst0, .variant = ..error) {
        status_code = 13
        return
    }
    if dst0..ok != 3 {
        status_code = 12
        return
    }

    dst1 ::= get#(.t: UInt8)(.self = &dst, .index = 1).result
    if is(.value = dst1, .variant = ..error) {
        status_code = 14
        return
    }
    if dst1..ok != 5 {
        status_code = 13
        return
    }

    dst2 ::= get#(.t: UInt8)(.self = &dst, .index = 2).result
    if is(.value = dst2, .variant = ..error) {
        status_code = 15
        return
    }
    if dst2..ok != 7 {
        status_code = 14
        return
    }

    dst3 ::= get#(.t: UInt8)(.self = &dst, .index = 3).result
    if is(.value = dst3, .variant = ..error) {
        status_code = 16
        return
    }
    if dst3..ok != 11 {
        status_code = 15
        return
    }
    status_code = 0
    }
}
}
}
}
