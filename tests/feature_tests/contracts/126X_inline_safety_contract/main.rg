Cell: Type = (.value: Int32)
Reader#(.Left: Type, .Right: Type): Contract = (
    .Result: Type
    .read: (.left: &Left, .right: &Right) -> (.result: Result) where depends_on(result, left)
)
implement Reader#(Cell, Cell) (
    .Result: Type = &Int32
    .read = (.left: &Cell, .right: &Cell) -> (.result: Result) { result = &right&.value }
)
main := () -> () {}
