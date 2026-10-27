Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant, .other: &Int32) -> (.first: &Int32, .second: &Int32)
    where {
        depends_on(first, self)
        depends_on(second, other)
    }
)

Cell := (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell, .other: &Int32) -> (.first: &Int32, .second: &Int32) {
    first = &self&.value
    second = other
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(40)
    other :: Int32 = 2
    source ::= to_virtual#(Source)(&cell)
    values ::= get(&source, &other)

    if values.first&+ values.second&!= 42 {
        status_code = 1
    }
}
