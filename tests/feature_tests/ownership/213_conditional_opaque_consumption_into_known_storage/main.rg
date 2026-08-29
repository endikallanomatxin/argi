Container : Type = (.marker: UInt8)

store_conditionally(
    .storage: $&Container,
    .slot: $&Int32,
    .source: $&Int32,
    .skip: Bool,
) -> () := {
    if skip {
        return
    }
    trusted_opaque_store_owned_in#(.t: Int32, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

main(.skip: Bool = false) -> (.status_code: Int32) := {
    container ::= Container(.marker = 0)
    slot :: Int32 = 0
    source :: Int32 = 7
    store_conditionally(.storage = $&container, .slot = $&slot, .source = $&source, .skip = skip)
    trusted_opaque_release_all(.storage = $&container)
    status_code = 0
}
