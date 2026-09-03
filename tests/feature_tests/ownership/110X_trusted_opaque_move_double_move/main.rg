main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    first :: Int32 = 0
    second :: Int32 = 0
    trusted_opaque_move#(.t: Int32)(.destination = $&first, .source = ~value)
    trusted_opaque_move#(.t: Int32)(.destination = $&second, .source = ~value)
    status_code = 0
}
