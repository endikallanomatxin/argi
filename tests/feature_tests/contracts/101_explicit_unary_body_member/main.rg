Readable#(.Input: Type): Contract = (
    read(.source: &Input) -> (.value: Result)
    .Result: Type
)
Cell: Type = (.value: Int32)
satisfies Readable#(Cell) = (.Result: Int32)
read(.source: &Cell) -> (.value: Readable#(Cell).Result) := {
    value = source&.value
}
main() -> (.status_code: Int32 = 0) := {
    cell ::= Cell(42)
    if read(&cell).value != 42 { abort }
}
