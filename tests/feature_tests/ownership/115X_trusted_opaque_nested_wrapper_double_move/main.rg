inner#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_store#(.t: t)(.destination = slot, .source = ~value)
}

outer#(.t: Type)(.slot: $&t, .value: t) -> () := {
    inner#(.t: t)(.slot = slot, .value = ~value)
}

main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    first :: Int32 = 0
    second :: Int32 = 0
    outer(.slot = $&first, .value = ~value)
    outer(.slot = $&second, .value = ~value)
    status_code = 0
}
