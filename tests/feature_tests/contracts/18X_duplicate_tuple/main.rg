Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: &Left, .right: &Right) -> (.value: Result) where {}
)
Row: Type = (.value: Int32)
Column: Type = (.value: Int32)
satisfies Product#(Row, Column) = (.Result: Int32)
satisfies Product#(.Right: Column, .Left: Row) = (.Result: Int64)
multiply(.left: &Row, .right: &Column) -> (.value: Int32) := {
    value = left&.value * right&.value
}
main() -> () := {}
