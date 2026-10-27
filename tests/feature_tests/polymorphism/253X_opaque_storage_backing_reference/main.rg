Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant, .storage: &Int32) -> (.reference: &Int32) where {
        from_storage(reference, storage)
    }
)

Cell: Type = ()

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell, .storage: &Int32) -> (.reference: &Int32) {
    reference = storage
}

main := () -> () {
    cell ::= Cell()
    _ ::= to_virtual#(Source)(&cell)
}
