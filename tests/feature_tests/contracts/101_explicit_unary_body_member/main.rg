Readable#(.Input: Type): Contract = (
    .read: (.source: &Input) -> (.value: Result)
    .Result: Type
)
Cell: Type = (.value: Int32)
implement Readable#(Cell) (.Result: Type = Int32, .read = _impl_read_178)
_impl_read_178 := (.source: &Cell) -> (.value: Readable#(Cell).Result)  {
    value = source&.value
}
main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    if read(&cell).value != 42 { abort }
}
