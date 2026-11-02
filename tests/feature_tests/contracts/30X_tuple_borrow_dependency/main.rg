First#(.Left: Type, .Right: Type): Contract = (
    .first : (.left: &Left, .right: &Right) -> (.value: &Left) where depends_on(value, left)
)

Cell := (.value: Int32)

implement First#(Cell, Cell) (.first = _impl_first_197)

_impl_first_197 := (.left: &Cell, .right: &Cell) -> (.value: &Cell) { value = right }

main := () -> () {
    left ::= Cell(1)
    right ::= Cell(2)
    borrowed ::= First#(Cell, Cell).first(&left, &right).value
}
