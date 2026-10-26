Base<.Value: Type>: Contract = (
    .read : (.source: &Value) -> (.value: Int32)
)

Combined<.Value: Type>: Contract = (Base<Value>)

Cell := (.value: Int32)

_cell_read := (.source: &Cell) -> (.value: Int32) { value = source&.value }

implement Base<Cell> (.read = _cell_read)

implement Combined<Cell> ()

consume := <.Value: Type: Combined> (.source: Value) -> (.value: Int32) {
    value = read(&source)
}

main := () -> (.status_code: Int32 = 0) {
    if consume(Cell(42)).value != 42 { abort }
}
