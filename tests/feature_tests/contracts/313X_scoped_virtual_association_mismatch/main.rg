Readable<.Participant: Type>: Contract = (
    .Other : Type
    .read  : (.other: &Other, .source: &Participant) -> (.value: &Int32)
    where depends_on(value, source)
)

Cell := (.value: Int32)

_cell_read := (.other: &Cell, .source: &Cell) -> (.value: &Int32) { value = &source&.value }

implement Readable<Cell> (.Other: Type = Cell, .read = _cell_read)

main := () -> () {
    other ::= Cell(7)
    source ::= Cell(42)
    handle ::= to_virtual<.contract: Readable<.Other: Cell>>(.value = &source)
    value ::= Readable<.Other: Float64>.read(&other, &handle)
}
