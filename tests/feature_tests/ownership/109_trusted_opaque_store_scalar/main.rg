main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    slot :: Int32 = 0
    trusted_opaque_store_owned#(.t: Int32)(.destination = $&slot, .source = ~value)
    status_code = slot
}
