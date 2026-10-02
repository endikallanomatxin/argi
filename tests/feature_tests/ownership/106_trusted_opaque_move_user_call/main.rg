main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    slot :: Int32 = 0
    trusted_opaque_move#(.t: Int32)(.destination = $&slot, .source = ~value)
    status_code = 0
}
