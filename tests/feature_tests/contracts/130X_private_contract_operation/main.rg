api := import ("./api")

Cell := (.value: Int32)

implement api.Reader#(Cell) (
    .Result : Type = Int32
    ._read  = (.value: &Cell) -> (.result: Result) { result = value&.value }
)

main := () -> () {
    cell ::= Cell(42)
    api.Reader#(Cell)._read(&cell)
}
