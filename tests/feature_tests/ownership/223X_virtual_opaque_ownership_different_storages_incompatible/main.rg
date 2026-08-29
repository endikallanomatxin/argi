OpaqueStorer : Abstract = (
    store(
        .self: $&Self,
        .first_storage: $&Container,
        .second_storage: $&Container,
        .slot: $&Int32,
        .source: $&Int32,
    ) -> ()
)

Container : Type = (.marker: UInt8)
First : Type = (.marker: UInt8)
Second : Type = (.marker: UInt8)
First implements OpaqueStorer
Second implements OpaqueStorer

store(
    .self: $&First,
    .first_storage: $&Container,
    .second_storage: $&Container,
    .slot: $&Int32,
    .source: $&Int32,
) -> () := {
    trusted_opaque_store_owned_in#(.t: Int32, .storage_type: Container)(
        .storage = first_storage,
        .destination = slot,
        .source = ~source&,
    )
}

store(
    .self: $&Second,
    .first_storage: $&Container,
    .second_storage: $&Container,
    .slot: $&Int32,
    .source: $&Int32,
) -> () := {
    trusted_opaque_store_owned_in#(.t: Int32, .storage_type: Container)(
        .storage = second_storage,
        .destination = slot,
        .source = ~source&,
    )
}

register_second(.value: $&Second) -> () := {
    _ ::= to_virtual#(.abstract: OpaqueStorer)(.value = value)
}

main() -> (.status_code: Int32) := {
    second ::= Second(.marker = 0)
    register_second(.value = $&second)
    first ::= First(.marker = 0)
    _ ::= to_virtual#(.abstract: OpaqueStorer)(.value = $&first)
    status_code = 0
}
