Resettable#(.Participant: Type): Contract = (
    .reset : (.self: $&Participant) -> () where {}
)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

Cell := (.resource: Resource)

implement Resettable#(Cell) (.reset = _impl_reset_Cell)

_impl_reset_Cell := (.self: $&Cell) -> () {
    deinit($&self&.resource)
}

main := () -> () {
    cell ::= Cell(Resource(42))
    handle ::= to_virtual#(Resettable)($&cell)
}
