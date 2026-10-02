store_wrapper#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_move#(.t: t)(.destination = slot, .source = ~value)
}

main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    slot :: Int32 = 0
    store_wrapper(.slot = $&slot, .value = ~value)
    status_code = value
}
