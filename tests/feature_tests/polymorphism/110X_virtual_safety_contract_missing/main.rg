Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant) -> (.value: Int32)
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: Int32) { value = self&.value }

main := () -> () {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)
}
