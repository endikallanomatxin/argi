First#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .first : (.left: &Left, .right: &Right) -> (.value: Result) where depends_on(value, left)
)

Cell := (.value: Int32)

implement First#(Cell, Cell) (.Result: Type = &Cell, .first = _impl_first_236)

_impl_first_236 := (.left: &Cell, .right: &Cell) -> (.value: First#(Cell, Cell).Result) {
    value = left
}

borrow := #(.A: Type, .B: Type) (.left: &A, .right: &B) -> (.value: First#(A, B).Result) {
    value = first(left, right).value
}

escape := () -> (.value: First#(Cell, Cell).Result) {
    left ::= Cell(42)
    right ::= Cell(7)
    value = borrow(&left, &right).value
}

main := () -> () { escape() }
