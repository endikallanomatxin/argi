OpaqueStorer#(.Participant: Type): Contract = (
    .store: (
        .self           : $&Participant,
        .first_storage  : $&Container,
        .second_storage : $&Container,
        .slot           : $&Int32,
        .source         : $&Int32,
    ) -> () where {}
)

Container: Type = (.marker: UInt8)

First: Type = (.marker: UInt8)

Second: Type = (.marker: UInt8)

implement OpaqueStorer#(First) (.store = _impl_store_First)
implement OpaqueStorer#(Second) (.store = _impl_store_Second)

_impl_store_First := (
        .self           : $&First,
        .first_storage  : $&Container,
        .second_storage : $&Container,
        .slot           : $&Int32,
        .source         : $&Int32,
    ) -> ()  {
    trusted_opaque_move_in#(.t: Int32, .storage_type: Container)(
        .storage     = first_storage
        .destination = slot
        .source      = ~source&
    )
}

_impl_store_Second := (
        .self           : $&Second,
        .first_storage  : $&Container,
        .second_storage : $&Container,
        .slot           : $&Int32,
        .source         : $&Int32,
    ) -> ()  {
    trusted_opaque_move_in#(.t: Int32, .storage_type: Container)(
        .storage     = second_storage
        .destination = slot
        .source      = ~source&
    )
}

register_second(.value: $&Second) -> () := {
    _ ::= to_virtual#(.contract: OpaqueStorer)(.value = value)
}

main() -> (.status_code: Int32) := {
    second ::= Second(.marker = 0)
    register_second(.value = $&second)
    first ::= First(.marker = 0)
    _ ::= to_virtual#(.contract: OpaqueStorer)(.value = $&first)
    status_code = 0
}
