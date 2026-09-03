main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    src_result ::= allocate(.self = $&allocator, .size = 4)
    match src_result {
    ..error _ { status_code = 10 }
    ..ok ~ src_payload {
    src_allocation ::= ~src_payload
    dst_result ::= allocate(.self = $&allocator, .size = 4)
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

    src[0] = 3
    src[1] = 5
    src[2] = 7
    src[3] = 11

    memcpy_bytes(.dst = dst, .src = src)

    if dst[0] != 3 {
        status_code = 12
    } else {
        if dst[1] != 5 {
            status_code = 13
        } else {
            if dst[2] != 7 {
                status_code = 14
            } else {
                if dst[3] != 11 {
                    status_code = 15
                } else {
                    status_code = 0
                }
            }
        }
    }
    }
    }
    }
    }

}
