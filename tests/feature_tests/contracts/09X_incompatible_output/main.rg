Readable#(.Participant: Type): Contract = (
    .read: (.source: &Participant) -> (.value: Int32) where {}
)

Cell: Type = (.value: Int32)

implement Readable#(Cell) (.read = _impl_read_Cell)

_impl_read_Cell := (.source: &Cell) -> (.value: Float64)  { value = 2.5 }

consume#(.source_type: Type: Readable)(.source: &source_type) -> (.value: Int32) := {
    value = read(source)
}

main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    if consume(&cell).value != 42 { abort }
}
