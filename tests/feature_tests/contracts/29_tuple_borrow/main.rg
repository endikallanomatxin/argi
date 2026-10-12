First#(.Left: Type, .Right: Type): Contract = (
    first(.left: &Left, .right: &Right) -> (.value: &Left) where depends_on(value, left)
)
Cell: Type = (.value: Int32)
satisfies First#(Cell, Cell)
first(.left: &Cell, .right: &Cell) -> (.value: &Cell) := { value = left }
main() -> () := {
    left ::= Cell(42)
    right ::= Cell(7)
    result ::= first(&left, &right)
    if result&.value != 42 { abort }
}
