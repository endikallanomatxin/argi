store_wrapper#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_store#(.t: t)(.destination = slot, .source = ~value)
}

inner#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_store#(.t: t)(.destination = slot, .source = ~value)
}

outer#(.t: Type)(.slot: $&t, .value: t) -> () := {
    inner#(.t: t)(.slot = slot, .value = ~value)
}

main() -> (.status_code: Int32) := {
    value :: Int32 = 42
    slot :: Int32 = 0
    store_wrapper(.slot = $&slot, .value = ~value)

    nested_value :: Int32 = 7
    nested_slot :: Int32 = 0
    outer(.slot = $&nested_slot, .value = ~nested_value)
    status_code = slot + nested_slot - 7
}
