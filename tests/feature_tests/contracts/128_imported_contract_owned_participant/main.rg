api := import ("./api")

Cell := (.value: Int32)

implement api.Reader<Cell> (
    .Result : Type = Int32
    .read   = (.value: &Cell) -> (.result: Result) { result = value&.value }
)

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(42)
    if api.Reader<Cell>.read(&cell).result != 42 { abort }
}
