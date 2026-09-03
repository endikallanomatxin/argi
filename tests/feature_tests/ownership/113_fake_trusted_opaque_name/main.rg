trusted_opaque_move(.destination: $&Int32, .source: Int32) -> () := {
    destination& = 0
}

main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    slot :: Int32 = 1
    trusted_opaque_move(.destination = $&slot, .source = value)
    status_code = slot
}
