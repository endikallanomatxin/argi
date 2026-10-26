First<.Left: Type, .Right: Type>: Contract = (
    .first : (.left: &Left, .right: &Right) -> (.value: &Left) where depends_on(value, left)
)

Cell := (.value: Int32)

implement First<Cell, Cell> (.first = _impl_first_197)

_impl_first_197 := (.left: &Cell, .right: &Cell) -> (.value: &Cell) { value = left }

main := () -> () {
    left ::= Cell(42)
    right ::= Cell(7)
    result ::= first(&left, &right)
    if result&.value != 42 { abort }
}
