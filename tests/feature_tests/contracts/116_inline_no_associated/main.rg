Cell: Type = (.value: Int32)
Check#(.T: Type): Contract = (
    .check: (.value: &T) -> (.result: Bool)
)
implement Check#(Cell) (
    .check = (.value: &Cell) -> (.result: Bool) {
        result = value&.value == 7
    }
)
main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(7)
    if Check#(Cell).check(&cell).result == false { abort }
}
