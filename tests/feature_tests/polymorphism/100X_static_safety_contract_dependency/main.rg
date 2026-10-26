Source<.Participant: Type>: Contract = (
    .get : (.self: &Participant, .other: &Int32) -> (.value: &Int32)
    where depends_on(value, self)
)

Cell := (.value: Int32)

implement Source<Cell> (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell, .other: &Int32) -> (.value: &Int32) {
    value = other
}

main := () -> () {
    cell ::= Cell(42)
    other :: Int32 = 7
    value ::= get(&cell, &other)
}
