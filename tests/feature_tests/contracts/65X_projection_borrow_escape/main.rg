First#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    first(.left: &Left, .right: &Right) -> (.value: Result) where depends_on(value, left)
)
Cell: Type = (.value: Int32)
satisfies First#(Cell, Cell) = (.Result: &Cell)
first(.left: &Cell, .right: &Cell) -> (.value: First#(Cell, Cell).Result) := { value = left }
borrow#(.A: Type, .B: Type)(.left: &A, .right: &B) -> (.value: First#(A, B).Result) := { value = first(left, right).value }
escape() -> (.value: First#(Cell, Cell).Result) := {
    left ::= Cell(42)
    right ::= Cell(7)
    value = borrow(&left, &right).value
}
main() -> () := { escape() }
