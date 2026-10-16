main() -> (.status_code: Int32 = 0) := {
    values :: [0]UInt8 = ()
    borrowed_view ::= view(.self = $&values)
    readonly ::= view(.self = &values)
    if length(.self = &borrowed_view).count != 0 { status_code = 1 }
    if length(.self = &readonly).count != 0 { status_code = 2 }
    read ::= get_reference(.self = &readonly, .index = 0).result
    write ::= set#(.t: UInt8)(.self = $&borrowed_view, .index = 0, .value = 7).result
    if is(.value = read, .variant = ..error) == false { status_code = 3 }
    if is(.value = write, .variant = ..error) == false { status_code = 4 }
    memcpy_bytes(.dst = borrowed_view, .src = readonly)
    memcpy_bytes(.dst = borrowed_view, .src = borrowed_view)
}
