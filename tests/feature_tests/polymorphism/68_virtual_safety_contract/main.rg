Source#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.value: &Int32)
    where depends_on(value, self)
)

Cell: Type = (.value: Int32)

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.value: &Int32)  {
    value = &self&.value
}

read_source(.source: &Virtual#(Source)) -> (.value: Int32) := {
    reference ::= get(source)
    value = reference&
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    source ::= to_virtual#(Source)(&cell)

    if read_source(&source) != 42 {
        status_code = 1
    }
}
