First: Contract#(.Left: Type, .Right: Type) = (
    first(.left: &Left, .right: &Right) -> (.value: &Left) where depends_on(value, left)
)
Cell: Type = (.value: Int32)
satisfies First#(Cell, Cell)
first(.left: &Cell, .right: &Cell) -> (.value: &Cell) := { value = right }
main() -> () := {}
