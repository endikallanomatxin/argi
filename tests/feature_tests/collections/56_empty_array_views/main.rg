main() -> (.status_code: Int32 = 0) := {
    values :: [0]UInt8 = ()
    view ::= array_view#(.n = 0, .t: UInt8)(.array = $&values).view
    readonly ::= array_view_ro#(.n = 0, .t: UInt8)(.array = &values).view
    if length#(.t: UInt8)(.self = &view).count != 0 { status_code = 1 }
    if length#(.t: UInt8)(.self = &readonly).count != 0 { status_code = 2 }
    read ::= get_ro_ref#(.t: UInt8)(.self = &readonly, .index = 0).result
    write ::= set#(.t: UInt8)(.self = $&view, .index = 0, .value = 7).result
    if is(.value = read, .variant = ..error) == false { status_code = 3 }
    if is(.value = write, .variant = ..error) == false { status_code = 4 }
    memcpy_bytes(.dst = view, .src = readonly)
    memcpy_bytes(.dst = view, .src = view)
}
