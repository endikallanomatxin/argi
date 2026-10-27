Cell := (.value: Int32)

Reader#(.Left: Type, .Right: Type): Contract = (
    .Result : Type
    .read   : (.left: &Left, .right: &Right) -> (.result: Result) where depends_on(result, left)
)

implement Reader#(Cell, Cell) (
    .Result : Type = &Int32
    .read   = (.left: &Cell, .right: &Cell) -> (.result: Result) { result = &left&.value }
)

main := () -> (.status_code: Int32 = 0) {
    left ::= Cell(42)
    right ::= Cell(7)
    if Reader#(Cell, Cell).read(&left, &right).result&!= 42 { abort }
}
