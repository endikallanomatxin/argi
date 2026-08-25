main() -> (.status_code: Int32) #trusted_temporal := {
    src_raw ::= malloc(.size = 4)
    dst_raw ::= malloc(.size = 4)

    if cast#(.to: UIntNative)(.value = src_raw) == 0 {
        status_code = 10
        return
    }

    if cast#(.to: UIntNative)(.value = dst_raw) == 0 {
        free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = src_raw)))
        status_code = 11
        return
    }

    src ::= array_view#(.t: UInt8)(
        .data = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = src_raw)),
        .length = 4,
    )
    dst ::= array_view#(.t: UInt8)(
        .data = cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = dst_raw)),
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

    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = src_raw)))
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = dst_raw)))
}
