main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    src_allocation ::= allocate_owned(.self = $&allocator, .size = 4)
    dst_allocation ::= allocate_owned(.self = $&allocator, .size = 4)

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
