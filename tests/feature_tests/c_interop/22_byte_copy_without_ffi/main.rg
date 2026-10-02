main() -> (.status_code: Int32 = 0) := {
    source :: [4]UInt8 = (2, 3, 5, 7)
    target :: [4]UInt8 = zeroed#(.t: [4]UInt8)()
    target_view ::= view($&target)
    memcpy_bytes(.dst = target_view, .src = view(&source))
    if unwrap_or_abort(.value = get#(.t: UInt8)(.self = &target_view, .index = 2)) != 5 { status_code = 1 }
    second :: [4]UInt8 = zeroed#(.t: [4]UInt8)()
    second_view ::= view($&second)
    memcpy_bytes(.dst = second_view, .src = target_view)
    if unwrap_or_abort(.value = get#(.t: UInt8)(.self = &second_view, .index = 3)) != 7 { status_code = 2 }
    empty :: [0]UInt8 = zeroed#(.t: [0]UInt8)()
    memcpy_bytes(.dst = view($&empty), .src = view(&source))
}
