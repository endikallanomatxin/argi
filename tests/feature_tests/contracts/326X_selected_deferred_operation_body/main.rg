Reader#(.Value: Type): Contract = (
    .Result : Type
    .read   : (.value: &Value) -> (.result: Result)
)

Cell := (.value: Int32)

implement Reader#(Cell) (
    .Result : Type = Int32
    .read   = (.value: &Cell) -> (.result: Result) {
        result = missing_operation().result
    }
)

main := () -> () {
    cell ::= Cell(42)
    result ::= Reader#(Cell).read(&cell).result
}
