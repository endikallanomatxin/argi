Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant, .other: &Int32) -> (.count: Int32, .result: ?&Int32) where {
        on result ..some { depends_on(result, self) }
        on result ..none {}
    }
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell, .other: &Int32) -> (.count: Int32, .result: ?&Int32) {
    count = 1
    result = ..some(.value = other)
}

main := () -> () {

    cell ::= Cell(42)
    other :: Int32 = 7
    source ::= to_virtual#(Source)(&cell)
    values ::= get(&source, &other)
}
