fake := import ("./fake")

main := () -> (.status_code: Int32) {
    value :: Int32 = 42
    slot :: Int32 = 1
    fake.trusted_opaque_move(.destination = $&slot, .source = value)
    status_code = slot
}
