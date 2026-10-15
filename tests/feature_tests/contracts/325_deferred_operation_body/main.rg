Reader#(.Value: Type): Contract = (
    .Result: Type
    .read: (.value: &Value) -> (.result: Result)
)
Cell: Type = (.value: Int32)
implement Reader#(Cell) (
    .Result: Type = Int32
    .read = (.value: &Cell) -> (.result: Result) {
        result = missing_operation().result
    }
)
main := () -> () {}
