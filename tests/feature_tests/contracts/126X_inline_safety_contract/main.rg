Cell := (.value: Int32)

Reader<.Left: Type, .Right: Type>: Contract = (
    .Result : Type
    .read   : (.left: &Left, .right: &Right) -> (.result: Result) where depends_on(result, left)
)

implement Reader<Cell, Cell> (
    .Result : Type = &Int32
    .read   = (.left: &Cell, .right: &Cell) -> (.result: Result) { result = &right&.value }
)

main := () -> () {
    left ::= Cell(1)
    right ::= Cell(2)
    borrowed ::= Reader<Cell, Cell>.read(&left, &right).result
}
