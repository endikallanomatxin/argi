OpaqueStorer : Abstract = (
    store(
        .self: $&Self,
        .storage: $&Container,
        .slot: $&Borrowing,
        .source: $&Borrowing,
    ) -> ()
)

Borrowing : Type = (.reference: $&UInt8)
Container : Type = (.marker: UInt8)
Keeping : Type = (.marker: UInt8)
Consuming : Type = (.marker: UInt8)
Keeping implements OpaqueStorer
Consuming implements OpaqueStorer

deinit(.self: $&Borrowing) -> () := {}

store(
    .self: $&Keeping,
    .storage: $&Container,
    .slot: $&Borrowing,
    .source: $&Borrowing,
) -> () := {}

store(
    .self: $&Consuming,
    .storage: $&Container,
    .slot: $&Borrowing,
    .source: $&Borrowing,
) -> () := {
    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.abstract: OpaqueStorer)(.value = value)
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    slot_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = slot_storage.data).reference
                    container ::= Container(.marker = 0)
                    keeping ::= Keeping(.marker = 0)
                    register_keeping(.value = $&keeping)
                    implementation ::= Consuming(.marker = 0)
                    virtual ::= to_virtual#(.abstract: OpaqueStorer)(.value = $&implementation)
                    source ::= Borrowing(.reference = target.data)
                    store(.self = $&virtual, .storage = $&container, .slot = slot, .source = $&source)
                    deinit(.self = $&target)
                    if source.reference& == 0 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
